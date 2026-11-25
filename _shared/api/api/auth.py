from django.conf import settings
from django.contrib.auth.models import User
from rest_framework import authentication, exceptions

import jwt


class JWTAuth(authentication.BaseAuthentication):
    def authenticate(self, request):
        header = request.META.get("HTTP_AUTHORIZATION", "")
        if not header.startswith("Bearer "):
            return None
        raw = header[7:].strip()
        try:
            payload = jwt.decode(raw, settings.JWT_KEY, algorithms=["HS256"])
        except Exception as exc:  # expired / tampered / wrong key
            raise exceptions.AuthenticationFailed(f"invalid token: {exc.__class__.__name__}")
        try:
            user = User.objects.get(pk=payload.get("sub"))
        except User.DoesNotExist:
            raise exceptions.AuthenticationFailed("unknown subject")
        return (user, payload)


def issue_token(user, role):
    import datetime
    payload = {
        "sub": user.id,
        "email": user.email,
        "role": role,
        "iat": datetime.datetime.now(datetime.timezone.utc),
        "exp": datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(hours=8),
    }
    return jwt.encode(payload, settings.JWT_KEY, algorithm="HS256")
