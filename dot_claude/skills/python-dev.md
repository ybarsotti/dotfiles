---
globs: ["**/*.py", "**/pyproject.toml", "**/setup.py"]
---

# Python Development

## Testing (pytest)

### Structure
```python
# Use fixtures over setup/teardown
@pytest.fixture
def client():
    return TestClient(app)

# Parametrize for edge cases
@pytest.mark.parametrize("input,expected", [
    ("", None),
    ("valid", "result"),
])
def test_function(input, expected):
    assert function(input) == expected
```

### Mocking
```python
# Mock external services
def test_api_call(mocker):
    mocker.patch("module.requests.get", return_value=Mock(status_code=200))

# Mock async
@pytest.mark.asyncio
async def test_async(mocker):
    mocker.patch("module.fetch", return_value=AsyncMock(return_value=data))
```

### Performance Tests
```python
# Assert query counts
def test_no_n_plus_one(django_assert_num_queries):
    with django_assert_num_queries(1):
        list(Model.objects.select_related("relation").all())
```

## Type Hints

### Modern Syntax (Python 3.10+)
```python
# Use built-in generics
def process(items: list[str]) -> dict[str, int]: ...

# Use | for unions
def fetch(id: int | None = None) -> User | None: ...

# Use Self for fluent interfaces
from typing import Self
def chain(self) -> Self: ...
```

### Common Patterns
```python
from typing import TypeVar, Protocol, Callable
from collections.abc import Iterable, Mapping

T = TypeVar("T")

# Protocol for duck typing
class Readable(Protocol):
    def read(self) -> bytes: ...
```

## Async Patterns

### Concurrent Execution
```python
# Run multiple coroutines
results = await asyncio.gather(*tasks, return_exceptions=True)

# With timeout
async with asyncio.timeout(10):
    result = await slow_operation()

# Semaphore for rate limiting
sem = asyncio.Semaphore(10)
async with sem:
    await api_call()
```

## Project Structure
```
src/
├── module/
│   ├── __init__.py
│   ├── models.py
│   ├── services.py
│   └── api.py
tests/
├── conftest.py
├── test_models.py
└── test_services.py
pyproject.toml
```

## Dependencies
- Use `pyproject.toml` over `setup.py`
- Pin versions in `requirements.txt`
- Use `pip-tools` for dependency resolution
