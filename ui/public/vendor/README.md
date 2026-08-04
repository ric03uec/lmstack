# Vendor marks

Ship an SVG here named after the probe's `gpu.vendor` string and the Instances
page renders it in place of the built-in stylised fallback:

    nvidia.svg      # served at /vendor/nvidia.svg
    amd.svg         # served at /vendor/amd.svg

`nvidia.svg` and `amd.svg` ship in this directory — their paths come from
[simple-icons](https://simpleicons.org/) (CC0), wrapped in a brand-hue tile
so the SVG file is self-contained: no CSS on the consuming end has to know
the vendor's colour. `VendorMark` in `../../src/routes/Instances.tsx` falls
back to a stylised geometric mark if a file is missing, so the SPA still
renders on a checkout with this directory empty.

To swap in a different mark — a company brand asset, a different icon set —
overwrite the SVG here. Nothing in the SPA code needs to change.
