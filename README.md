# Fillform

Fill PDF forms in pure Ruby, with the same output as pdftk.

Fillform fills AcroForm templates in process and draws every filled field with the layout of pdftk
(iText 2.1.7): font size, baseline, comb cells, line breaks, alignment, background and border, list
and combo boxes. It has no dependencies: no Java, no pdftk binary, no subprocess, no other gem. It
reads and writes the PDF files itself.

It ships the API of the [pdf-forms](https://github.com/jkraemer/pdf-forms) gem, so it replaces
pdf-forms without changing your code, and your documents keep looking the same.

## Installation

```ruby
gem "fillform"
```

## Usage

```ruby
Fillform.fill("template.pdf", "filled.pdf", { name: "Hans Müller", newsletter: "Yes" }, flatten: true)

Fillform.fields("template.pdf")
# => [#<struct Fillform::Field name="name", type="Text", flags="0", justification="Left", max_length=nil, ...>, ...]
```

Text fields and combo boxes get the value as a string, list boxes a string or an array of export
values, check boxes and radio buttons the name of their state (`"Off"` to uncheck them). Values for
fields the template does not have are ignored. With `flatten: true` the fields are drawn into the
pages and removed, like pdftk does it.

## Replacing pdf-forms

```diff
- gem "pdf-forms"
+ gem "fillform", require: "fillform/pdf_forms"
```

Replace an explicit `require "pdf_forms"` with `require "fillform/pdf_forms"`, or drop it.
`PdfForms.new` now returns a Fillform wrapper. The path to pdftk is accepted and ignored, so
`PdfForms.new(PDFTK_EXE, data_format: "XFdf")` keeps working, and you can uninstall pdftk.

| pdf-forms                                          | Fillform                                        |
|----------------------------------------------------|-------------------------------------------------|
| `fill_form(template, destination, data, flatten:)` | supported, nested hashes too                    |
| `get_fields`, `get_field_names`, `read(path)`      | supported, same `Field` attributes and values   |
| `data_format: "Fdf"`, `"XFdf"`, `"FdfHex"`         | supported, see below                            |
| `utf8_fields: true`                                | always on                                       |
| `PdfForms::PdftkError`                             | an alias of `Fillform::Error`                   |
| `cat`, `stamp`, `multistamp`, `call_pdftk`         | not supported: use CombinePDF or Prawn          |
| `encrypt`, `drop_xfa`, `drop_xmp`, `need_appearances`, `replacement_font` | raise `Fillform::Error` |

### Data formats

pdf-forms does not hand the values to pdftk as they are: each data format changes them on the way,
and those changes are visible in the documents. Fillform reproduces them, so that the drop-in
replacement draws exactly what pdftk drew:

- **Fdf**, the default: values are written in ISO-8859-15 and read back by pdftk in PDFDocEncoding.
  Characters outside ISO-8859-15 become `?`, `€` becomes `¤`, `œ` becomes `½` and a non-breaking
  space becomes `€`. Every line feed and carriage return breaks a line.
- **XFdf**: runs of the same space, tab or line feed collapse into one, so blank lines disappear.
- **FdfHex**: values arrive as they are.

`Fillform.fill` always takes the values as they are. To get rid of the Fdf substitutions while
keeping the pdf-forms API, pass `data_format: "FdfHex"`.

## How close to pdftk?

The appearance streams are built with the formulas of pdftk's iText 2.1.7, read from its bytecode
where its behaviour was not obvious: line breaking (`BidiLine`), split characters, auto font size,
list box scrolling, Java's `Cp1252` and `MacRoman` charsets, single precision box sizes,
`java.awt.Color` rounding, the order of the field states. Flattening follows iText too: the fields
are drawn in the order of their names, at the lower left corner of their widgets, only when they are
printed and not hidden, and the form keeps an empty field list.

It was verified by filling the same random values through pdftk and Fillform and comparing the
field metadata and, for every text and choice field, the text drawn (font size, position and bytes
of every line) and the background and border. The values included line breaks, long words, hyphens,
tabs, non-breaking spaces, whitespace only and characters the fonts do not have. On these templates,
in all three data formats, nothing differed:

| templates                                                                    | files | fields |
|------------------------------------------------------------------------------|------:|-------:|
| production templates of four applications                                    |    65 |  2,584 |
| IRS forms (W-9, W-4, 1040, 941, ...)                                         |     9 |    770 |
| the form test files of [pdf-lib](https://github.com/Hopding/pdf-lib) and [pdf.js](https://github.com/mozilla/pdf.js) | 30 | 1,008 |
| a synthetic template with every border, color, alignment and field kind      |     1 |  1,463 |

Each template was filled several times with different values: more than 57,000 field appearances,
none different from pdftk's: every number in the appearance streams is equal to the last digit, because
the layout is computed with Java's single precision floats and written with iText's number format.

pdftk does not use the iText 2.1.7 release as it is: pdftk-java ships its own fork of it, and that
fork draws some fields differently, for example comb fields, list boxes and characters the font
cannot show. Fillform follows pdftk, since pdftk is what it replaces.

### Known differences

- pdftk leaves a check box without any appearance when its value is not one of the box's states
  and the state names are not ASCII. Fillform leaves such a box as it is in the template.
- Encrypted templates are not supported.
- Fonts are read like iText reads simple fonts (Type 1 and TrueType with a single byte encoding).
  A composite (Type 0) font in the default appearance of a field is not supported.
- The output is a single revision with the objects the document uses, in a cross-reference table,
  like pdftk writes it; object streams of the template are written out as plain objects.

## Speed

Fill and flatten, then read the fields, on a 32 thread Linux workstation with OpenJDK 26 and Ruby 4.0:

| template                     | fields | pdftk fill | Fillform fill | pdftk fields | Fillform fields |
|------------------------------|-------:|-----------:|--------------:|-------------:|----------------:|
| contract                     |     30 |     124 ms |         12 ms |        71 ms |            4 ms |
| salary certificate           |     39 |     129 ms |         16 ms |        69 ms |            4 ms |
| instant card                 |      3 |      88 ms |          3 ms |        49 ms |            1 ms |
| company application, 4 pages |    131 |     160 ms |         70 ms |       100 ms |           12 ms |

## License

Fillform is released under the MIT License.

The files in `data/` are Adobe's: the metrics of the 14 standard fonts (`data/afm`, distributed
under the terms in `data/afm/MustRead.html`) and the Adobe Glyph List (`data/agl`, BSD 3-Clause,
see `data/agl/LICENSE.md`).
