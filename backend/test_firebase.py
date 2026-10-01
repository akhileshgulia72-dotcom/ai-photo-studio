import os

import firebase_admin
from firebase_admin import credentials
from dotenv import load_dotenv

load_dotenv()

service_account_path = os.getenv("FIREBASE_SERVICE_ACCOUNT_JSON")

if not service_account_path:
    raise RuntimeError("FIREBASE_SERVICE_ACCOUNT_JSON is missing from .env")

print("Service account path:")
print(service_account_path)

if not os.path.exists(service_account_path):
    raise RuntimeError(
        f"Service account file does not exist: {service_account_path}"
    )

cred = credentials.Certificate(service_account_path)

firebase_admin.initialize_app(cred)

print("================================")
print("Firebase Admin SDK: CONNECTED")
print("Project ID:", cred.project_id)
print("================================")