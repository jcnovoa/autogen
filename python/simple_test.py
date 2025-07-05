#!/usr/bin/env python3
"""
Simple test to verify AutoGen installation and basic functionality
"""
import asyncio
from autogen_agentchat.agents import AssistantAgent
from autogen_core.models import ChatCompletionClient, SystemMessage, UserMessage, AssistantMessage, CreateResult
from typing import List, Any, Dict, Optional, AsyncGenerator, Union


class MockChatCompletionClient(ChatCompletionClient):
    """Mock client for testing without API keys"""
    
    def __init__(self, model: str = "mock-gpt-4"):
        self._model = model
    
    async def create(
        self,
        messages: List[Union[SystemMessage, UserMessage, AssistantMessage]],
        *,
        model: Optional[str] = None,
        **kwargs: Any,
    ) -> CreateResult:
        # Simple mock response
        return CreateResult(
            content="Hello World! This is a mock response from AutoGen.",
            finish_reason="stop",
            usage={"prompt_tokens": 10, "completion_tokens": 15, "total_tokens": 25},
            cached=False,
        )
    
    async def create_stream(
        self,
        messages: List[Union[SystemMessage, UserMessage, AssistantMessage]],
        *,
        model: Optional[str] = None,
        **kwargs: Any,
    ) -> AsyncGenerator[Union[str, CreateResult], None]:
        # Mock streaming response
        words = ["Hello", " World!", " This", " is", " a", " mock", " streaming", " response."]
        for word in words:
            yield word
        
        yield CreateResult(
            content="",
            finish_reason="stop",
            usage={"prompt_tokens": 10, "completion_tokens": 15, "total_tokens": 25},
            cached=False,
        )
    
    def actual_usage(self) -> Dict[str, Any]:
        return {"total_tokens": 25}
    
    def total_usage(self) -> Dict[str, Any]:
        return {"total_tokens": 25}
    
    def count_tokens(self, messages: List[Union[SystemMessage, UserMessage, AssistantMessage]], **kwargs: Any) -> int:
        return sum(len(str(msg.content)) for msg in messages)
    
    def remaining_tokens(self, messages: List[Union[SystemMessage, UserMessage, AssistantMessage]], **kwargs: Any) -> int:
        return 4000 - self.count_tokens(messages, **kwargs)
    
    async def close(self) -> None:
        pass


async def main() -> None:
    print("🚀 Starting AutoGen Simple Test...")
    
    try:
        # Test basic imports
        print("📦 Testing imports...")
        import autogen_core
        import autogen_agentchat
        import autogen_ext
        print(f"✅ autogen-core version: {autogen_core.__version__}")
        print(f"✅ autogen-agentchat version: {autogen_agentchat.__version__}")
        print("✅ All packages imported successfully!")
        
        # Create a mock model client (no API key needed)
        print("\n🤖 Creating mock model client...")
        model_client = MockChatCompletionClient(model="mock-gpt-4")
        
        # Create an assistant agent
        print("👤 Creating assistant agent...")
        agent = AssistantAgent("assistant", model_client=model_client)
        
        print("📝 Running agent with task: 'Say Hello World!'")
        
        # Run the agent
        result = await agent.run(task="Say 'Hello World!'")
        
        print(f"🤖 Agent Response: {result}")
        
        # Clean up
        await model_client.close()
        
        print("✅ AutoGen simple test completed successfully!")
        
    except Exception as e:
        print(f"❌ Error during test: {e}")
        import traceback
        traceback.print_exc()


if __name__ == "__main__":
    asyncio.run(main())
