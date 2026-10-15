# Annotation spec

`annotate.py` reads one JSON file. Paths resolve against the directory of that file.
All coordinates are CSS px, the unit that `shoot.sh` writes to `*.boxes.txt`.

```json
{
  "scale": 2,
  "tones": { "teal": [13, 148, 136] },
  "shots": [
    {
      "src": "raw/dashboard.png",
      "out": "screenshots/01-dashboard-new-cards.png",
      "title": "1 · Dashboard: the two new cards",
      "source": "live",
      "source_note": "local stack · sales rep persona · October 14, 2026",
      "crop": [200, 20, 1240, 640],
      "dim": 70,
      "marks": [
        {
          "box": [305, 48, 844, 270],
          "label": "New card: order open over 30 days",
          "label_at": [872, 58],
          "tone": "amber"
        }
      ]
    }
  ]
}
```

## Fields

| Field | Required | Meaning |
|---|---|---|
| `scale` | no | Device scale factor of the captures. Default 2. A shot can override it. |
| `tones` | no | Extra colors as RGB. Built in: `green`, `amber`, `red`, `blue`, `purple`. |
| `src` | yes | The raw capture. |
| `out` | yes | The annotated image. The script creates the directory. |
| `title` | no | Bold caption line in the bottom banner. Start it with the image number. |
| `source` | no | `live` (green line) or `fixture` (amber line). Any other text prints in grey. |
| `source_note` | no | Text after the source label: environment, persona, date. |
| `crop` | no | `[x0, y0, x1, y1]` of the raw capture. Mark coordinates stay in the uncropped space. |
| `dim` | no | Darkness outside the boxes, 0 to 255. Default 70. Use 0 for no dimming. |
| `marks[].box` | yes | `[left, top, right, bottom]` of the element. |
| `marks[].label` | yes | The callout text. Keep it under about 50 characters. |
| `marks[].label_at` | no | Top-left corner of the callout pill. Without it, the script places the pill right of the box, else left of it (centered on the box vertically), else above it, else under it. The pill always stays inside the image. |
| `marks[].tone` | no | Color of the box, the leader line and the number. Default `green`. An unknown tone stops the script with the list of valid tones. |

## Numbering

The script numbers the marks in list order and prints the legend after each image.
Put the marks in the order the notes explain them. Reuse the printed legend for the
notes, so the numbers in the text and in the image are the same.

## Tone convention

- `green`: the new thing the image is about.
- `blue`: navigation, context, or an existing control the reader must find.
- `amber`: a warning state, an estimate, or a derived value.
- `red`: an error or an issue flag.

## Placement rules

- Put each pill in empty space: a margin, the space under a card, or a blank column.
- Do not let a pill cover text that another mark points at.
- Keep leader lines short. Avoid lines that cross another pill.
- Two marks may share a box when one element has two facts to explain.
- Crop to the region the marks cover, plus some context. A full 1440 px page makes small text unreadable.
