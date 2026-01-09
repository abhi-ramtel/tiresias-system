#!/usr/bin/env python3
"""
LLM Analysis Module
Scene description and analysis using Ollama
"""

import asyncio
import base64
import httpx
from typing import Optional, Dict, Any, List

# Ollama configuration
OLLAMA_BASE_URL = "http://localhost:11434"
DEFAULT_MODEL = "llava"  # Vision-capable model for image analysis


class LLMAnalyzer:
    """LLM-based scene analyzer using Ollama"""
    
    def __init__(self, model: str = DEFAULT_MODEL, base_url: str = OLLAMA_BASE_URL):
        """
        Initialize the LLM analyzer
        
        Args:
            model: Ollama model name (should be vision-capable like llava)
            base_url: Ollama API base URL
        """
        self.model = model
        self.base_url = base_url
        self.client = httpx.AsyncClient(timeout=30.0)
        
    async def analyze_image(
        self,
        image_bytes: bytes,
        prompt: str = "Describe what you see in this image. Focus on objects, people, and activities.",
        context: Optional[List[Dict[str, Any]]] = None
    ) -> str:
        """
        Analyze an image using the vision LLM
        
        Args:
            image_bytes: JPEG image data
            prompt: Analysis prompt
            context: Optional list of previous detections for context
            
        Returns:
            Text description of the scene
        """
        # Encode image to base64
        image_b64 = base64.b64encode(image_bytes).decode("utf-8")
        
        # Build prompt with context if provided
        full_prompt = prompt
        if context:
            objects = [d["class"] for d in context]
            full_prompt = f"Objects detected: {', '.join(objects)}. {prompt}"
        
        # Call Ollama API
        try:
            response = await self.client.post(
                f"{self.base_url}/api/generate",
                json={
                    "model": self.model,
                    "prompt": full_prompt,
                    "images": [image_b64],
                    "stream": False
                }
            )
            response.raise_for_status()
            result = response.json()
            return result.get("response", "Unable to analyze image")
            
        except httpx.HTTPError as e:
            return f"Error analyzing image: {str(e)}"
            
    async def describe_scene(self, image_bytes: bytes, detections: List[Dict[str, Any]]) -> str:
        """
        Generate a natural language description of the scene
        
        Args:
            image_bytes: JPEG image data
            detections: List of YOLO detections
            
        Returns:
            Natural language scene description
        """
        prompt = (
            "You are helping a visually impaired person understand their surroundings. "
            "Describe this scene in a clear, helpful way. "
            "Mention important objects, their positions, and any potential hazards or points of interest."
        )
        return await self.analyze_image(image_bytes, prompt, context=detections)
        
    async def answer_question(self, image_bytes: bytes, question: str) -> str:
        """
        Answer a question about the image
        
        Args:
            image_bytes: JPEG image data
            question: User's question
            
        Returns:
            Answer to the question
        """
        prompt = f"Looking at this image, please answer: {question}"
        return await self.analyze_image(image_bytes, prompt)
        
    async def check_health(self) -> bool:
        """Check if Ollama is available"""
        try:
            response = await self.client.get(f"{self.base_url}/api/tags")
            return response.status_code == 200
        except:
            return False
            
    async def close(self):
        """Close the HTTP client"""
        await self.client.aclose()


# Global instance
_analyzer: Optional[LLMAnalyzer] = None

async def get_analyzer() -> LLMAnalyzer:
    """Get or create the global LLM analyzer instance"""
    global _analyzer
    if _analyzer is None:
        _analyzer = LLMAnalyzer()
    return _analyzer


if __name__ == "__main__":
    async def test():
        print("Testing LLM analyzer...")
        analyzer = LLMAnalyzer()
        
        # Check health
        healthy = await analyzer.check_health()
        print(f"Ollama available: {healthy}")
        
        if not healthy:
            print("⚠️  Ollama not running. Start with: ollama serve")
            print("   Then pull a vision model: ollama pull llava")
            
        await analyzer.close()
        
    asyncio.run(test())
