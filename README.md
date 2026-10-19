# Nest (Skink)

A flexible configuration management library for Skink applications that
supports loading configuration from environment variables and configuration
files (JSON, YAML, XML) with a cascading priority system.

This is a port of the Go `nest` module (`github.com/markoxley/nest`) to
Skink, adapted to Skink's compile-time reflection model.

## Features

- **Multi-source configuration**: Load from environment variables, files, or both
- **Cascading priorities**: File values → Environment variables → Default values
- **Field tag-based**: Declarative configuration using `[attr]` field tags
- **Nested struct support**: Section types registered once, then recursed automatically
- **Typed fields**: `string`, `int`, `int64`, `float`, `bool` are all supported
- **Default config generation**: Create sample config files from your structs
- **Environment discovery**: List all recognized environment variables

## Files

- `nest.skink` — the library (`module nest`)
- `nest_test.skink` — test suite mirroring the Go tests

## Using the module

Copy `nest.skink` into your project, or place it on the module search path
(vendor directory, `.skink/cache`, or alongside your sources):

```
yourproject/
  vendor/
    nest.skink        (or vendor/nest/nest.skink)
  main.skink
```

Then `import "nest"`.

## Quick Start

```skink
module main

import "nest"
import "std/errors"
import "std/fs"
import "std/io"
import "std/reflect"

struct AppConfig {
    [env(APP_HOST,localhost)] [json(name=host)] [yaml(name=host)]
    host: string
    [env(APP_PORT,8080)] [json(name=port)] [yaml(name=port)]
    port: string
    [env(APP_DEBUG,false)] [json(name=debug)] [yaml(name=debug)]
    debug: bool
}

pub fn main() {
    var cfg AppConfig
    t := reflect.TypeOf<AppConfig>(cfg)

    // Load from environment, then override with config.json
    err := nest.Load(t, int64(&cfg), "APP", []string{"config.json"})
    if err.message != "" {
        if !fs.Exists("config.json") {
            io.PrintErrorLine("config.json not found, using env/defaults only")
        } else {
            io.PrintErrorLine("load error: " + err.message)
            return
        }
    }

    io.PrintLine("Server will start on " + cfg.host + ":" + cfg.port)
}
```

## API

The Go version passes the config struct and uses runtime reflection. Skink
generics erase type parameters, so — following the `std/orm` convention —
the reflected type and the struct address are passed explicitly:

```skink
pub fn Load(t: reflect.Type, ptr: int64, prefix: string, files: []string) -> errors.Error
pub fn MustLoad(t: reflect.Type, ptr: int64, prefix: string, files: []string)
pub fn ListEnvironmentVariables(t: reflect.Type, prefix: string) -> (map[string]string, errors.Error)
pub fn CreateDefaultConfig(t: reflect.Type, filename: string, filetype: string) -> errors.Error
pub fn Register(t: reflect.Type)
```

Call sites look like:

```skink
var cfg MyConfig
t := reflect.TypeOf<MyConfig>(cfg)
err := nest.Load(t, int64(&cfg), "APP", []string{"app.json"})
err2 := nest.CreateDefaultConfig(t, "config.yaml", "")
m, lerr := nest.ListEnvironmentVariables(t, "APP")
```

`files` may contain a second element naming the file type explicitly —
`[]string{"myconfig", "json"}` — accepting `"json"` or `".json"` spellings
(this fixes a Go quirk where `filepath.Ext("json")` returned `""`).
`filetype` in `CreateDefaultConfig` works the same way; pass `""` to infer
from the filename.

## Field Tags

Skink expresses Go struct tags as `[attr]` / `[attr(args)]` annotations
above the field. Stacked tags are space-joined, so several can go on one line
or on separate lines.

### `[env(...)]` — environment loading

```skink
struct Config {
    [env(HOST,localhost)]   // load from HOST env var, default "localhost"
    host: string
    [env(PORT)]             // load from PORT env var, no default
    port: string
    [env(-)]                // excluded from env loading
    secret: string
}
```

Format: `[env(VAR_NAME,default)]` or `[env(-)]` to exclude. As in Go, an
untagged leaf field is still looked up by its (uppercased) field name —
the env tag only renames and adds a default. Only tagged fields appear in
`ListEnvironmentVariables`/`CreateDefaultConfig` output.

Environment and default values are converted to the field's declared type:
`string` fields keep the raw text; `int`/`int64`/`float`/`bool` fields are
parsed (a bad value is a load error naming the field). Field types outside
that set (slices, maps, `int8`/`uint*`, function pointers...) are
"unsupported" — an error is returned only if a value actually targets them.

### `[json(...)]` / `[yaml(...)]` / `[xml(...)]` — file keys

```skink
struct Config {
    [env(DB_HOST,localhost)] [json(name=database_host)]
    databaseHost: string          // maps to {"database_host": "..."} in JSON
    [env(DB_PORT,5432)] [yaml(database_port)]   // positional form also works
    databasePort: string          // maps to database_port: ... in YAML
    [json(ignore)]
    transient: string             // excluded from JSON loading
}
```

`[json(name=x)]`/`[yaml(name=x)]`/`[xml(name=x)]` rename the key;
`[json(x)]` positional form works too; `[json(ignore)]` or `[json(-)]`
excludes the field — matching `std/json`'s tag conventions.

## Nested Structs

Go reflects into nested structs automatically. Skink's `reflect` cannot
resolve a field's type name back to its fields, so each nested (section)
type must be registered once:

```skink
struct DatabaseConfig {
    [env(HOST,localhost)]
    host: string
    [env(PORT,5432)]
    port: string
}

struct Config {
    database: DatabaseConfig
    [env(API_KEY)]
    apiKey: string
}

nest.Register(reflect.TypeOf<DatabaseConfig>(DatabaseConfig{host: "", port: ""}))
```

With prefix `"APP"`, the recognized variables are `APP_DATABASE_HOST`,
`APP_DATABASE_PORT`, `APP_APIKEY`. An `[env(NAME)]` tag on the section
field itself overrides the section prefix (e.g. `[env(BASE)]` →
`BASE_HOST`). An unregistered nested type is a load-time error naming the
type — call `nest.Register` for it.

### Pointer fields

`*Struct` fields are auto-detected — reflected type names distinguish
`"*Struct"` pointer fields from `"Struct"` inline fields and `"[]T"` slice
fields:

```skink
struct Config {
    database: *DatabaseConfig   // auto-allocated and zeroed if nil
}
```

A nil pointer is heap-allocated before loading. The `[nest(ptr)]`
annotation is still accepted for compatibility but is no longer required.
Slice, map, set, and pointer-to-primitive fields are not supported.

## Loading Priority

Values are loaded in the following order (highest to lowest):

1. **Configuration file** — values present in the file take precedence
2. **Environment variables** — override defaults when set
3. **Field tag defaults** — used when the env var is not set
4. **Zero values** — type defaults if nothing else is available

When loading from files, **only keys present in the file are updated**;
other fields keep their env/default values. JSON/YAML values must match
the field's kind (a number will not load into a `string` field — an error,
as in Go). XML element text is converted like environment text.

## Supported File Types

- **JSON** (`.json`)
- **YAML** (`.yaml`, `.yml`)
- **XML** (`.xml`) — loading supported; `CreateDefaultConfig` for XML
  returns an error (as in Go)

## Differences from the Go version

- **API shape**: `reflect.Type` + `int64(&cfg)` parameters instead of
  `interface{}` (generic erasure means `TypeOf` must run at the call site).
- **Tags**: `[env(VAR,def)]`/`[json(name=x)]` annotations instead of
  `env:"VAR,def"`/`json:"x"` backtick tags.
- **Nested structs**: require `nest.Register(...)` per section type.
- **Pointer fields**: `*Struct` fields are auto-detected and allocated
  when nil (the `[nest(ptr)]` marker is accepted but optional).
- **Embedded structs**: Go's anonymous-field promotion has no Skink
  equivalent.
- **Typed fields**: env/default strings are converted to `int`/`float`/`bool`
  fields (Go would panic via `SetString`); file loaders enforce JSON/YAML
  kind matching.
- **Missing-file detection**: `Load` returns a `nest: cannot read config
  file "...": open failed` error — check `fs.Exists` instead of
  `errors.Is(err, os.ErrNotExist)`.
- **ListEnvironmentVariables** returns `(map, Error)` and lists registered
  nested types unconditionally (Go skips nil `*Struct` fields, a
  value-dependent check impossible at type level).

## Running the tests

```bash
SKINK_HOME=/path/to/skink skink -t skinknest
```

## License

MIT License — see LICENSE file for details.

## Author

Mark Oxley
