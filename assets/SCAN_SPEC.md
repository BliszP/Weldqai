
# WeldQAi Scan Hints (x-weldqai)

We extend JSON Schema with a vendor key `x-weldqai.scan` to tell the UI which fields support scanning.

## Scalar field example
```json
"jointId": {
  "type": "string",
  "x-weldqai": { "scan": { "mode": "picker", "regex": "^(?P<jointId>[A-Za-z0-9\-_/\.]+)$", "dest": "value" } }
}
```
- `mode`: `"barcode" | "text" | "picker"` (picker lets the UI choose).
- `regex`: optional pattern; if it defines named groups, the UI may route to fields by group name; otherwise, full match becomes the value.
- `dest`: `"value"` for the current field (default).

## Bulk example (Pipe Tally)
Top-level schema can include:
```json
"x-weldqai": {
  "scan": {
    "mode": "picker",
    "bulk": {
      "appendTo": "tally",
      "rowPattern": "^(?P<pipeId>[^,]+),(?P<heatNumber>[^,]+),(?P<lengthM>\\d+(?:\\.\\d+)?)$",
      "delimiter": "\n+"
    }
  }
}
```
The UI should parse each scanned line via `rowPattern` and append an item to `properties.tally.items` mapping by the named groups.
