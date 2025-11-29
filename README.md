# limeka editor

- this is a port of a port([Waqar144/lite-odin](https://github.com/Waqar144/lite-odin)) of [rxi/lite](https://github.com/rxi/lite)
- It uses [`umka`](https://github.com/vtereshkov/umka-lang) instead of Lua
- most of the odin code is exact copy from `lite-odin`
- i did this to mostly learn umka
- the umka code is very much an copy of lua code as seen in original codebase. Because of this it fails to use lots of improvements that are possible due to umka e.g. enums, etc.
- some parts of original lua code make use of try/catch behaviour which is not possible in umka by design and so not implemented

## Build instructions

- install [Odin](https://odin-lang.org/docs/install/)
- `odin build . -vet`
- To enable `umprof`, build it with `UMPROF` flag

  `odin build . -vet -define:UMPROF=true`

> NOTE:
> 1. the executable and `data/` must be in the same dir
> 2. There are probably bugs not fixed yet.
> 3. It has memory leaks
> 4. not tested in windows at all
