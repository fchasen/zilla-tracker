# Conduit transport

How Conduit calls are encoded, sent, and decoded.

## Overview

[Conduit](https://secure.phabricator.com/book/phabricator/article/conduit/) is Phabricator's RPC convention. Every endpoint is invoked the same way: a `POST` to `<baseURL>/api/<endpoint>` with a form-encoded body. Phabricator returns a JSON envelope wrapping either the result or an error.

PhabricatorKit hides all of this behind ``PhabricatorClient``'s typed methods, but understanding the wire format helps when debugging or extending the library.

## The request

Every request is `POST <baseURL>/api/<endpoint>` with `Content-Type: application/x-www-form-urlencoded`.

The body has two fields:

```
api.token=<token>&params=<json>
```

`api.token` is the legacy form parameter. The `<json>` blob also carries the token under `__conduit__.token`:

```json
{
  "__conduit__": { "token": "cli-xxxxxxxxxxxxxxxxxxxxxxxxx" },
  "queryKey": "active",
  "constraints": { "authorPHIDs": ["PHID-USER-aaa"] },
  "limit": 50
}
```

PhabricatorKit emits both for forward and backward compatibility.

### Encoding pipeline

1. The query value (e.g. ``RevisionQuery``) is encoded to JSON via a `JSONEncoder` configured with sorted keys and a custom date strategy. ``PhabricatorClient/makeEncoder()`` exposes this configuration.
2. The token is injected into the resulting JSON object as `__conduit__.token` by `PhabricatorClient.wrapParams(_:token:encoder:)`.
3. The combined string is form-encoded via `ConduitFormBody.encode(token:paramsJSON:)`, which percent-encodes both fields per RFC 3986.

## The response

Conduit always returns HTTP 200, even on errors. Successful payloads look like:

```json
{
  "result": { "data": [ … ], "cursor": { … } },
  "error_code": null,
  "error_info": null
}
```

Errors arrive in the same envelope:

```json
{
  "result": null,
  "error_code": "ERR-CONDUIT-CORE",
  "error_info": "Invalid api.token"
}
```

PhabricatorKit's internal `ConduitEnvelope<T>` decodes both shapes. When `error_code` is non-nil the client throws ``PhabricatorError/api(code:info:)``.

## Error mapping

| Server condition | Thrown error |
|------------------|--------------|
| Network failure (URLSession `URLError`) | ``PhabricatorError/network(_:)`` |
| HTTP 401 | ``PhabricatorError/unauthorized`` |
| HTTP non-2xx (other) | ``PhabricatorError/invalidResponse`` |
| JSON decode failure | ``PhabricatorError/decoding(_:)`` |
| `error_code` present in envelope | ``PhabricatorError/api(code:info:)`` |
| Endpoint requires a token but auth is `.none` | ``PhabricatorError/missingToken`` |

## Pagination

All `*Query` types support cursor-based pagination via `before` / `after` / `limit`:

```swift
var query = RevisionQuery.active(authorPHID: me.phid)
query.limit = 50

var page = try await client.searchRevisions(query)
while let after = page.cursor.after {
    query.after = after
    page = try await client.searchRevisions(query)
    // …
}
```

## Decoding leniency

Phabricator forks sometimes emit numeric IDs as strings, booleans as ints, or rename transaction types (for example `differential.inline` vs. `differential:inline`). The model decoders in PhabricatorKit accept both shapes wherever this happens in the wild — see ``RevisionTransaction``'s decoding for the most thorough example.
