from flask import Flask, jsonify

app = Flask(__name__)

NAME = "Zahra Ismail"  # change if needed

@app.get("/")
def home():
    # Simple creative page + popup
    return f"""
    <!doctype html>
    <html>
    <head>
      <meta charset="utf-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1" />
      <title>Fargate Live</title>
      <style>
        body {{ font-family: Arial, sans-serif; margin: 0; background: #0b1220; color: #e6e6e6; }}
        .wrap {{ max-width: 900px; margin: 0 auto; padding: 40px 20px; }}
        .card {{ background: rgba(255,255,255,0.06); border: 1px solid rgba(255,255,255,0.12);
                border-radius: 16px; padding: 28px; box-shadow: 0 12px 30px rgba(0,0,0,0.35); }}
        h1 {{ margin: 0 0 12px; font-size: 34px; }}
        .badge {{ display: inline-block; padding: 6px 10px; border-radius: 999px;
                 background: rgba(76,175,80,0.18); border: 1px solid rgba(76,175,80,0.35); }}
        .grid {{ display: grid; grid-template-columns: 1fr; gap: 14px; margin-top: 18px; }}
        .kv {{ background: rgba(255,255,255,0.05); border-radius: 12px; padding: 12px 14px; }}
        a {{ color: #8ab4ff; text-decoration: none; }}
        footer {{ opacity: 0.7; margin-top: 18px; font-size: 13px; }}
      </style>
    </head>
    <body>
      <div class="wrap">
        <div class="card">
          <div class="badge">✅ ECS Fargate — Deployment Successful</div>
          <h1>Hey! I’m {NAME} 👋</h1>
          <p>This app is running on <b>port 8080</b> and is ready for CI/CD 🚀</p>

          <div class="grid">
            <div class="kv">Health check: <a href="/health" target="_blank">/health</a></div>
            <div class="kv">Tip: If you see this page, your networking + ECS service are correct ✅</div>
          </div>

          <footer>
            Built for the CI/CD to AWS Fargate assignment.
          </footer>
        </div>
      </div>

      <script>
        // Popup style greeting
        window.onload = () => {{
          alert("🚀 Deployed! Hello from ECS Fargate\\n\\nOwner: {NAME}\\nStatus: Healthy ✅");
        }};
      </script>
    </body>
    </html>
    """

@app.get("/health")
def health():
    return jsonify(status="OK"), 200

if __name__ == "__main__":
    # Listen on all interfaces for container/ECS
    app.run(host="0.0.0.0", port=8080)
