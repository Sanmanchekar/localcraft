Drop your org's reference Dockerfiles here, named by stack:

```
samples/docker/python.Dockerfile
samples/docker/node.Dockerfile
samples/docker/go.Dockerfile
samples/docker/spring.Dockerfile
samples/docker/rails.Dockerfile
```

The skill will use the stack-matching reference when:
- The target repo has no `Dockerfile` and the user asks to generate one
- The user explicitly asks "use the python Dockerfile reference"

Keep these as production-ready multi-stage builds — they are the canonical recipe the skill copies from.
