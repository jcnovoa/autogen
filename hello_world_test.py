#!/usr/bin/env python3
"""
Simple Hello World test for AutoGen without requiring API keys
"""
import asyncio
from autogen_agentchat.agents import AssistantAgent
from autogen_core.models import ChatCompletionClient, ChatMessage, CreateChatCompletionResponse
from typing import List, Any, Dict, Optional, AsyncGenerator, Union
from autogen_core.models._types import CreateChatCompletionRequest


class MockChatCompletionClient(ChatCompletionClient):
    """Mock client for testing without API keys"""
    
    def __init__(self, model: str = "mock-gpt-4"):
        self._model = model
    
    async def create(
        self,
        messages: List[ChatMessage],
        *,
        model: Optional[str] = None,
        **kwargs: Any,
    ) -> CreateChatCompletionResponse:
        # Simple mock response
        return CreateChatCompletionResponse(
            content="Hello World! This is a mock response from AutoGen.",
            finish_reason="stop",
            usage={"prompt_tokens": 10, "completion_tokens": 15, "total_tokens": 25},
            cached=False,
        )
    
    async def create_stream(
        self,
        messages: List[ChatMessage],
        *,
        model: Optional[str] = None,
        **kwargs: Any,
    ) -> AsyncGenerator[Union[str, CreateChatCompletionResponse], None]:
        # Mock streaming response
        words = ["Hello", " World!", " This", " is", " a", " mock", " streaming", " response."]
        for word in words:
            yield word
        
        yield CreateChatCompletionResponse(
            content="",
            finish_reason="stop",
            usage={"prompt_tokens": 10, "completion_tokens": 15, "total_tokens": 25},
            cached=False,
        )
    
    def actual_usage(self) -> Dict[str, Any]:
        return {"total_tokens": 25}
    
    def total_usage(self) -> Dict[str, Any]:
        return {"total_tokens": 25}
    
    def count_tokens(self, messages: List[ChatMessage], **kwargs: Any) -> int:
        return sum(len(msg.content) for msg in messages if isinstance(msg.content, str))
    
    def remaining_tokens(self, messages: List[ChatMessage], **kwargs: Any) -> int:
        return 4000 - self.count_tokens(messages, **kwargs)
    
    async def close(self) -> None:
        pass


async def main() -> None:
    print("🚀 Starting AutoGen Hello World Test...")
    
    # Create a mock model client (no API key needed)
    model_client = MockChatCompletionClient(model="mock-gpt-4")
    
    # Create an assistant agent
    agent = AssistantAgent("assistant", model_client=model_client)
    
    print("📝 Running agent with task: 'Say Hello World!'")
    
    # Run the agent
    result = await agent.run(task="Say 'Hello World!'")
    
    print(f"🤖 Agent Response: {result}")
    
    # Clean up
    await model_client.close()
    
    print("✅ AutoGen Hello World test completed successfully!")


if __name__ == "__main__":
    asyncio.run(main())
