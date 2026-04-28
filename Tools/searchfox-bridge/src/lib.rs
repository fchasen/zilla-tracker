use once_cell::sync::OnceCell;
use searchfox_lib::{searchfox_url_repo, SearchOptions, SearchfoxClient};

uniffi::setup_scaffolding!();

const REPO: &str = "mozilla-central";

#[derive(Debug, Clone, uniffi::Record)]
pub struct SearchHit {
    pub path: String,
    pub line_number: u64,
    pub line: String,
    pub url: String,
}

#[derive(Debug, thiserror::Error, uniffi::Error)]
#[uniffi(flat_error)]
pub enum SearchfoxError {
    #[error("network: {0}")]
    Network(String),
    #[error("client init failed: {0}")]
    ClientInit(String),
    #[error("invalid query")]
    InvalidQuery,
}

fn client() -> Result<&'static SearchfoxClient, SearchfoxError> {
    static CLIENT: OnceCell<SearchfoxClient> = OnceCell::new();
    CLIENT.get_or_try_init(|| {
        let mut c = SearchfoxClient::new(REPO.to_string(), false)
            .map_err(|e| SearchfoxError::ClientInit(e.to_string()))?;
        c.set_cache_enabled(false);
        Ok(c)
    })
}

async fn run(opts: SearchOptions) -> Result<Vec<SearchHit>, SearchfoxError> {
    let client = client()?;
    let results = client
        .search(&opts)
        .await
        .map_err(|e| SearchfoxError::Network(e.to_string()))?;

    let display_repo = searchfox_url_repo(REPO);
    Ok(results
        .into_iter()
        .map(|r| {
            let url = if r.line_number == 0 {
                format!("https://searchfox.org/{}/source/{}", display_repo, r.path)
            } else {
                format!(
                    "https://searchfox.org/{}/source/{}#{}",
                    display_repo, r.path, r.line_number
                )
            };
            SearchHit {
                path: r.path,
                line_number: r.line_number as u64,
                line: r.line,
                url,
            }
        })
        .collect())
}

#[uniffi::export(async_runtime = "tokio")]
pub async fn search_files(path: String, limit: u32) -> Result<Vec<SearchHit>, SearchfoxError> {
    let trimmed = path.trim().to_string();
    if trimmed.is_empty() {
        return Err(SearchfoxError::InvalidQuery);
    }
    run(SearchOptions {
        query: None,
        path: Some(trimmed),
        limit: limit.max(1) as usize,
        ..Default::default()
    })
    .await
}

#[uniffi::export(async_runtime = "tokio")]
pub async fn search_identifiers(
    identifier: String,
    limit: u32,
) -> Result<Vec<SearchHit>, SearchfoxError> {
    let trimmed = identifier.trim().to_string();
    if trimmed.is_empty() {
        return Err(SearchfoxError::InvalidQuery);
    }
    run(SearchOptions {
        query: Some(format!("id:{trimmed}")),
        limit: limit.max(1) as usize,
        ..Default::default()
    })
    .await
}
