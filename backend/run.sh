#!/bin/bash
# Start the workout system backend server
cd "$(dirname "$0")"
pip install -q -r requirements.txt
python3 -m uvicorn main:app --host 0.0.0.0 --port 8000 --log-level info
