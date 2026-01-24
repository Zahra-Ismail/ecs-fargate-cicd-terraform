FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the App folder
COPY App/ ./App/

EXPOSE 8080

CMD ["python", "App/app/app.py"]
