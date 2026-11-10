FROM python:3.12-slim
WORKDIR /app
RUN useradd --system --uid 10001 omisha
COPY report_engine.py .
USER 10001:10001
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
ENTRYPOINT ["python", "/app/report_engine.py"]
