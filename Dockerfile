# Multi-stage build for AutoGen Studio
FROM node:18-alpine AS frontend-builder

# Install rsync for the build process
RUN apk add --no-cache rsync

# Set working directory for frontend build
WORKDIR /app/frontend

# Copy package files
COPY python/packages/autogen-studio/frontend/package.json .
COPY python/packages/autogen-studio/frontend/yarn.lock .

# Install dependencies
RUN yarn install --frozen-lockfile

# Copy frontend source code
COPY python/packages/autogen-studio/frontend/ .

# Create the target directory structure
RUN mkdir -p ../autogenstudio/web/ui

# Build frontend
RUN yarn build

# Production stage
FROM python:3.11-slim

# Set working directory
WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git \
    git-lfs \
    curl \
    build-essential \
    && rm -rf /var/lib/apt/lists/* \
    && git lfs install

# Install UV package manager
RUN pip install uv

# Copy Python project files
COPY python/pyproject.toml python/uv.lock ./

# Install Python dependencies
RUN uv sync --no-dev

# Copy Python application code
COPY python/ ./

# Copy built frontend from previous stage
COPY --from=frontend-builder /app/autogenstudio/web/ui ./packages/autogen-studio/autogenstudio/web/ui/

# Create non-root user for security
RUN useradd --create-home --shell /bin/bash autogen
RUN chown -R autogen:autogen /app
USER autogen

# Set environment variables
ENV PYTHONPATH=/app
ENV PORT=8080
ENV HOST=0.0.0.0

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=30s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8080/docs || exit 1

# Start command
CMD ["uv", "run", "autogenstudio", "ui", "--host", "0.0.0.0", "--port", "8080", "--database-uri", "${DATABASE_URI}"]
