# testpg
Postgres 17 ( Postgis base, PGVector and Apache Age extensions)

## Build
Yeah build the image
```bash
build_tag="pg/graphvector"
cd postgres && \
	docker build -t $build_tag .
```
