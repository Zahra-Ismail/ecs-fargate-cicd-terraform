from flask import Flask, jsonify

app = Flask(__name__)

@app.get("/")
def home():
    return "Hello from Flask on ECS Fargate!\n"

@app.get("/health")
def health():
    return jsonify(status="ok"), 200

if __name__ == "__main__":
    # Important: listen on 0.0.0.0 and port 8080
    app.run(host="0.0.0.0", port=8080)

