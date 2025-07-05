# AutoGen Application Stack Documentation

## Overview

AutoGen is a comprehensive multi-agent AI framework that supports both Python and .NET implementations. The framework provides a layered architecture for building AI agents, from low-level core components to high-level applications like AutoGen Studio.

## Architecture Layers

### 1. Core Layer
- **autogen-core**: Foundational interfaces and agent runtime implementation
- **Microsoft.AutoGen.Core** (.NET): Core runtime and messaging infrastructure

### 2. AgentChat Layer  
- **autogen-agentchat**: High-level API for rapid prototyping and common multi-agent patterns
- Built on top of the Core API, closest to AutoGen v0.2 experience

### 3. Extensions Layer
- **autogen-ext**: First and third-party extensions for expanding framework capabilities
- Includes LLM clients, code execution, web browsing, and specialized agents

### 4. Applications Layer
- **AutoGen Studio**: No-code GUI for building multi-agent applications
- **Magentic-One**: State-of-the-art multi-agent team for complex tasks
- **AutoGen Bench**: Benchmarking suite for evaluating agent performance

## Python Stack

### Core Requirements
- **Python Version**: 3.10 or later (required)
- **Package Manager**: UV (recommended) or pip
- **Build System**: Hatchling

### Core Packages and Versions

#### autogen-core (v0.6.2)
**Dependencies:**
- pillow >= 11.0.0
- typing-extensions >= 4.0.0
- pydantic < 3.0.0, >= 2.10.0
- protobuf ~= 5.29.3
- opentelemetry-api >= 1.34.1
- jsonref ~= 1.1.0
- opentelemetry-semantic-conventions == 0.55b1

#### autogen-agentchat (v0.6.2)
**Dependencies:**
- autogen-core == 0.6.2

#### autogen-ext (v0.6.2)
**Base Dependencies:**
- autogen-core == 0.6.2

**Optional Extensions:**
- **OpenAI**: openai >= 1.66.5, tiktoken >= 0.8.0, aiofiles
- **Anthropic**: anthropic >= 0.48
- **Azure**: azure-ai-inference >= 1.0.0b9, azure-ai-projects >= 1.0.0b11, azure-core, azure-identity, azure-search-documents >= 11.4.0
- **Web Surfer**: playwright >= 1.48.0, pillow >= 11.0.0, magika >= 0.6.1rc2, markitdown[all] ~= 0.1.0a3
- **Docker**: docker ~= 7.0, asyncio_atexit >= 1.0.1
- **Ollama**: ollama >= 0.4.7, tiktoken >= 0.8.0
- **Jupyter Executor**: ipykernel >= 6.29.5, nbclient >= 0.10.2
- **gRPC**: grpcio ~= 1.70.0
- **Semantic Kernel**: semantic-kernel >= 1.17.1
- **Gemini**: google-genai >= 1.0.0
- **Memory Systems**: chromadb >= 1.0.0, mem0ai >= 0.1.98
- **Video Processing**: opencv-python >= 4.5, ffmpeg-python, openai-whisper
- **HTTP Tools**: httpx >= 0.27.0, json-schema-to-pydantic >= 0.2.0
- **MCP**: mcp >= 1.8.1

#### AutoGen Studio (autogenstudio)
**Dependencies:**
- pydantic, pydantic-settings
- fastapi[standard]
- typer
- aiofiles
- python-dotenv
- websockets
- sqlmodel
- psycopg
- alembic
- loguru
- pyyaml
- html2text
- autogen-core >= 0.4.9.2, < 0.7
- autogen-agentchat >= 0.4.9.2, < 0.7
- autogen-ext[magentic-one, openai, azure] >= 0.4.2, < 0.7
- anthropic

#### Magentic-One CLI (v0.2.4)
**Dependencies:**
- autogen-agentchat >= 0.4.4, < 0.5
- autogen-ext[docker,openai,magentic-one,rich] >= 0.4.4, < 0.5
- pyyaml >= 5.1

### Development Dependencies
- **Type Checking**: pyright == 1.1.389, mypy == 1.13.0
- **Linting/Formatting**: ruff == 0.4.8
- **Testing**: pytest, pytest-asyncio, pytest-cov, pytest-xdist, pytest_mock
- **Task Runner**: poethepoet
- **Protocol Buffers**: grpcio-tools ~= 1.70.0, mypy-protobuf
- **Documentation**: sphinx, myst-nb, pydata-sphinx-theme
- **UI Frameworks**: chainlit >= 2.0.1, streamlit
- **Utilities**: typer, rich, polars, packaging, cookiecutter

### Installation Commands

#### Basic Installation
```bash
# Install AgentChat and OpenAI client
pip install -U "autogen-agentchat" "autogen-ext[openai]"

# Install AutoGen Studio
pip install -U "autogenstudio"

# Install Magentic-One CLI
pip install -U "magentic-one-cli"
```

#### Development Installation
```bash
# Clone repository
git clone https://github.com/microsoft/autogen.git
cd autogen/python

# Install with UV (recommended)
uv sync --dev

# Or with pip
pip install -e ".[dev]"
```

#### Web Browsing Capabilities
```bash
# Install web surfer extension
pip install -U autogen-agentchat autogen-ext[openai,web-surfer]

# Install Playwright browsers
playwright install
```

## .NET Stack

### Core Requirements
- **.NET SDK**: 9.0.100 (with rollForward: latestFeature)
- **Target Framework**: .NET 9.0
- **Package Management**: Central Package Management enabled

### Core Packages and Versions

#### Microsoft.AutoGen.Contracts
- Core contracts and interfaces for agent communication

#### Microsoft.AutoGen.Core  
- Core runtime implementation
- Event-driven agent system
- Message passing infrastructure

#### Microsoft.AutoGen.Core.Grpc
- gRPC-based communication layer
- Cross-language interoperability with Python

#### Microsoft.AutoGen.RuntimeGateway.Grpc
- Runtime gateway for distributed agent systems

### Key Dependencies
- **Microsoft.Extensions.AI**: 9.5.0 (Preview: 9.5.0-preview.1.25265.7)
- **Microsoft.Extensions.Configuration**: 9.0.0
- **Microsoft.Extensions.DependencyInjection**: 9.0.3
- **Microsoft.Extensions.Logging**: 9.0.0
- **Microsoft.Orleans**: 9.0.1
- **Semantic Kernel**: 1.45.0 (Preview/Alpha versions available)
- **Azure.AI.OpenAI**: 2.2.0-beta.4
- **Azure.AI.Inference**: 1.0.0-beta.1
- **Grpc.AspNetCore**: 2.67.0
- **CloudNative.CloudEvents.SystemTextJson**: 2.7.1

### Development Dependencies
- **Testing**: FluentAssertions 6.12.2, coverlet.collector 6.0.2
- **Aspire**: 9.0.0 (for cloud-native development)
- **Azure Services**: Various Azure SDK packages for cloud integration

### Installation Commands

#### .NET Package Installation
```bash
# Install core packages
dotnet add package Microsoft.AutoGen.Core
dotnet add package Microsoft.AutoGen.Core.Grpc

# Install contracts
dotnet add package Microsoft.AutoGen.Contracts

# Install runtime gateway
dotnet add package Microsoft.AutoGen.RuntimeGateway.Grpc
```

#### Development Setup
```bash
# Clone repository
git clone https://github.com/microsoft/autogen.git
cd autogen/dotnet

# Restore packages
dotnet restore

# Build solution
dotnet build
```

## Cross-Language Support

### Protocol Buffers
- **Version**: 5.29.3 (Python), 2.67.0 (.NET)
- **Purpose**: Cross-language message serialization
- **Files**: Located in `/protos` directory
- **Generation**: Automated via build tasks

### gRPC Communication
- **Python**: grpcio ~= 1.70.0
- **.NET**: Grpc.AspNetCore 2.67.0
- **Purpose**: Enable Python and .NET agents to communicate

## Development Environment

### Container Support
- **Base**: Development container with Docker support
- **Features**:
  - Docker-outside-of-Docker
  - .NET Aspire
  - Azure CLI
  - Git
  - .NET SDK
  - Azure Developer CLI (azd)
  - Python

### IDE Extensions (VS Code)
- ms-python.python
- ms-python.debugpy
- GitHub.copilot
- ms-dotnettools.csdevkit
- ms-dotnettools.vscodeintellicode-csharp
- github.vscode-github-actions

### Code Quality Tools
- **Python**: Ruff (formatting/linting), Pyright/MyPy (type checking)
- **.NET**: Built-in analyzers, EditorConfig
- **Testing**: pytest (Python), xUnit (.NET)
- **Coverage**: pytest-cov (Python), coverlet (.NET)

## External Service Dependencies

### AI Model Providers
- **OpenAI**: GPT-4o, GPT-3.5-turbo, embeddings
- **Azure OpenAI**: Same models via Azure
- **Anthropic**: Claude models
- **Google**: Gemini models
- **Ollama**: Local model serving
- **Azure AI**: Various Azure AI services

### Optional Services
- **Redis**: Caching and state management
- **PostgreSQL**: Database for AutoGen Studio
- **ChromaDB**: Vector database for embeddings
- **Neo4j**: Graph database for memory systems
- **Docker**: Container execution environment

## Deployment Options

### Local Development
- Direct Python/pip installation
- UV workspace management
- .NET SDK with NuGet packages

### Container Deployment
- Docker containers with multi-stage builds
- Development containers for consistent environments

### Cloud Deployment
- Azure Container Instances
- Azure App Service
- Kubernetes clusters
- Aspire cloud-native applications

## Performance and Scalability

### Concurrency
- **Python**: asyncio-based async/await patterns
- **.NET**: Task-based asynchronous programming
- **Orleans**: Actor model for distributed systems

### Monitoring
- OpenTelemetry instrumentation
- Azure Application Insights integration
- Custom logging and metrics

## Security Considerations

### API Keys Management
- Environment variables for sensitive data
- Azure Key Vault integration
- Secure credential storage

### Network Security
- HTTPS/TLS for all communications
- API key authentication
- Role-based access control

## Getting Started

### Quick Start (Python)
```bash
# Install basic components
pip install -U "autogen-agentchat" "autogen-ext[openai]"

# Set environment variable
export OPENAI_API_KEY="your-api-key"

# Run hello world example
python -c "
import asyncio
from autogen_agentchat.agents import AssistantAgent
from autogen_ext.models.openai import OpenAIChatCompletionClient

async def main():
    model_client = OpenAIChatCompletionClient(model='gpt-4o')
    agent = AssistantAgent('assistant', model_client=model_client)
    print(await agent.run(task='Say Hello World!'))
    await model_client.close()

asyncio.run(main())
"
```

### Quick Start (AutoGen Studio)
```bash
# Install AutoGen Studio
pip install -U "autogenstudio"

# Run on localhost:8080
autogenstudio ui --port 8080 --appdir ./my-app
```

### Quick Start (.NET)
```bash
# Create new project
dotnet new console -n MyAutoGenApp
cd MyAutoGenApp

# Add AutoGen packages
dotnet add package Microsoft.AutoGen.Core
dotnet add package Microsoft.AutoGen.Core.Grpc

# Build and run
dotnet build
dotnet run
```

This comprehensive stack provides everything needed to build sophisticated multi-agent AI applications, from simple chatbots to complex distributed systems with web browsing, code execution, and cross-language communication capabilities.
