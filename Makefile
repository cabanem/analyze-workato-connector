.PHONY: help install test clean run

help:
	@echo "Available commands:"
	@echo "  make install    Install dependencies"
	@echo "  make test       Run tests"
	@echo "  make clean      Remove Python cache files"
	@echo "  make run        Run the main application"

install:
	pip install --upgrade pip
	pip install -r requirements.txt

test:
	python -m pytest tests/ -v

clean:
	find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
	find . -type f -name "*.pyc" -delete

run:
	python main.py
