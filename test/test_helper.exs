# The `:conformance` suite checks every compiled rule against the full
# date-holidays fixture corpus. It downloads a tarball on first run and is
# slow, so it is excluded by default; run it with `mix test --include
# conformance` (or `--only conformance`).
ExUnit.start(exclude: [:conformance])
