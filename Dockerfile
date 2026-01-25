FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY App/ ./App/

WORKDIR /app/App/app

EXPOSE 8080

CMD ["python", "app.py"]
