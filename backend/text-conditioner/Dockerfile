FROM nvidia/cuda:12.1.1-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV PIP_NO_CACHE_DIR=1

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.10 python3-pip python3.10-venv git build-essential \
    libgl1 libglib2.0-0 && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/hunyuan3d1
RUN git clone --depth 1 https://github.com/Tencent-Hunyuan/Hunyuan3D-1.git . \
    && python3.10 -m pip install --upgrade pip \
    && python3.10 -m pip install torch==2.6.0 torchvision==0.21.0 \
       --index-url https://download.pytorch.org/whl/cu121 \
    && python3.10 -m pip install -r requirements.txt

WORKDIR /app
COPY requirements.txt .
RUN python3.10 -m pip install -r requirements.txt
COPY . .

ENV HUNYUAN1_REPO_PATH=/opt/hunyuan3d1
ENV HUNYUAN1_TEXT_MODEL_PATH=/opt/hunyuan3d1/weights/hunyuanDiT
ENV DABSKY_MODEL_DEVICE=cuda:0
EXPOSE 8090

CMD ["python3.10", "-m", "uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8090"]
