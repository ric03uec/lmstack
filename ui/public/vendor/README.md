# Vendor marks

Drop an SVG here named after the probe's `gpu.vendor` string, and the
Instances page will render it in place of the built-in stylised mark:

    nvidia.svg      # served at /vendor/nvidia.svg
    amd.svg         # served at /vendor/amd.svg

The `<img>` tag falls back to the built-in mark if the file is absent, so
this directory can stay empty. Nothing in the SPA code needs to change when
you add a file — `VendorMark` resolves the URL from the slug at render time.

## Why this indirection

The SPA ships stylised marks rather than the official trademarked wordmarks
so a fresh checkout runs without pulling assets from a vendor's site — and
so contributors do not paste screenshots of a trademarked logo into the
repo. If you want the real logo on your own dashboard, get it from the
vendor's brand kit (they are freely downloadable, sometimes with attribution
requirements) and put it here. The file is not committed by default.
