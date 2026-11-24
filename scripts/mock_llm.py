#!/usr/bin/env python3
"""Faux service LLM pour les essais du panneau de discussion : imite l'API Anthropic (/v1/messages) et une API compatible OpenAI
(/v1/chat/completions). Premier tour : l'« agent » demande l'outil get_state ; après le résultat de l'outil : il conclut « Terminé ».
Usage : mock_llm.py <port>   (écrit « prêt » sur la sortie standard ; vérifie la clé de test « test-key »)."""
import json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer

class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def send_json(self, code, obj):
        d = json.dumps(obj).encode(); self.send_response(code); self.send_header("content-type", "application/json"); self.send_header("content-length", str(len(d))); self.end_headers(); self.wfile.write(d)
    def do_GET(self):
        if self.path.startswith("/v1/models"):
            if "anthropic-version" in self.headers and self.headers.get("x-api-key") != "test-key": return self.send_json(401, {"error": {"type": "authentication_error", "message": "clé invalide"}})
            return self.send_json(200, {"data": [{"id": "test-model"}]})
        self.send_json(404, {"error": {"message": "inconnu"}})
    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers.get("content-length", 0))) or b"{}")
        if self.path == "/v1/messages":
            if self.headers.get("x-api-key") != "test-key": return self.send_json(401, {"error": {"type": "authentication_error", "message": "clé invalide"}})
            assert body.get("tools") and "mSLICE" in body.get("system", ""), "outils ou consigne absents"
            last = body["messages"][-1]
            if last["role"] == "user" and isinstance(last["content"], list) and last["content"][0].get("type") == "tool_result":
                txt = last["content"][0]["content"][0]["text"]
                return self.send_json(200, {"role": "assistant", "stop_reason": "end_turn", "content": [{"type": "text", "text": "Terminé : appli " + ("ouverte" if '"app_open" : true' in txt else "fermée")}]})
            return self.send_json(200, {"role": "assistant", "stop_reason": "tool_use", "content": [{"type": "text", "text": "Je regarde l'état."}, {"type": "tool_use", "id": "toolu_1", "name": "get_state", "input": {}}]})
        if self.path == "/v1/chat/completions":
            assert body.get("tools") and body["messages"][0]["role"] == "system", "outils ou consigne absents"
            if self.headers.get("authorization") != "Bearer test-key": return self.send_json(401, {"error": {"message": "clé invalide"}})
            last = body["messages"][-1]
            if last["role"] == "tool":
                return self.send_json(200, {"choices": [{"message": {"role": "assistant", "content": "Terminé : état lu (" + str(len(last["content"])) + " caractères)"}}]})
            return self.send_json(200, {"choices": [{"message": {"role": "assistant", "content": None, "tool_calls": [{"id": "call_1", "type": "function", "function": {"name": "get_state", "arguments": "{}"}}]}}]})
        self.send_json(404, {"error": {"message": "inconnu"}})

srv = HTTPServer(("127.0.0.1", int(sys.argv[1])), H)
print("prêt", flush=True)
srv.serve_forever()
