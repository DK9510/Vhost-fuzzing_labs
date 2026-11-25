import secrets

from django.conf import settings
from django.contrib.auth import authenticate
from django.contrib.auth.models import User
from django.core.mail import EmailMessage
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from .auth import issue_token
from .models import Chat, ResetToken


@api_view(["GET"])
def root(request):
    return Response(
        {
            "users": "/api/users/",
            "auth/password_reset": "/api/auth/password_reset",
            "auth/login": "/api/auth/login",
            "chats": "/api/chats",
            "chat-status": "/api/chat-status",
        }
    )


@api_view(["GET"])
def chat_status(request):
    return Response({"service": "chat-api", "status": "ok", "build": "2026.11.1"})


@api_view(["GET"])
def portal_home(request):
    """Public landing page of the keyword-routed portal app (lab C10)."""
    from django.http import HttpResponse

    return HttpResponse(
        "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>Portal</title></head>"
        "<body><h1>Portal</h1>"
        "<p>Employee services portal. Sign in to open your dashboard.</p>"
        "<p>Service status: /api/chat-status &middot; Dashboard: /dashboard</p>"
        "</body></html>"
    )


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def dashboard(request):
    """Authenticated dashboard: the state change that grades lab C10."""
    return Response(
        {
            "portal": "dashboard",
            "user": request.user.email,
            "role": "admin" if request.user.is_staff else "agent",
            "chats": Chat.objects.filter(owner=request.user).count(),
        }
    )


@api_view(["POST"])
def password_reset(request):
    """Draft the reset mail, then hand it to SMTP. The SMTP host is broken in this
    deployment, so the exception surfaces the drafted body in the traceback (C07)."""
    email = (request.data.get("email") or "").strip()
    user = User.objects.filter(email__iexact=email).first()
    if user is None:
        # no user enumeration: same answer either way
        return Response({"detail": "if the address exists, a reset mail was sent"},
                        status=status.HTTP_202_ACCEPTED)

    token_value = secrets.token_hex(16)
    ResetToken.objects.create(user=user, token=token_value)
    link = f"{settings.FRONT_URL}/chatadmin/reset?token={token_value}"
    body = (
        f"Hi {user.first_name or user.username},\n\n"
        "A password reset was requested for your chat console account.\n\n"
        f"Reset link: {link}\n"
        f"Token: token={token_value}\n\n"
        f"Requested from {request.META.get('REMOTE_ADDR', 'unknown')} at "
        f"{request.META.get('HTTP_USER_AGENT', 'unknown agent')}.\n\n"
        "If this was not you, contact the service desk.\n"
    )
    msg = EmailMessage(
        subject="Chat console password reset",
        body=body,
        from_email=settings.DEFAULT_FROM_EMAIL,
        to=[user.email],
    )
    # dead SMTP -> ConnectionRefusedError -> unhandled -> Django technical 500
    msg.send(fail_silently=False)
    return Response({"detail": "if the address exists, a reset mail was sent"},
                    status=status.HTTP_202_ACCEPTED)


@api_view(["POST"])
def password_reset_confirm(request):
    token_value = (request.data.get("token") or "").strip()
    password = request.data.get("password") or ""
    if len(password) < 8:
        return Response({"detail": "password too short"}, status=status.HTTP_400_BAD_REQUEST)
    row = ResetToken.objects.filter(token=token_value, used=False).first()
    if row is None:
        return Response({"detail": "invalid or already used token"},
                        status=status.HTTP_400_BAD_REQUEST)
    user = row.user
    user.set_password(password)
    user.save(update_fields=["password"])
    row.used = True
    row.save(update_fields=["used"])
    return Response({"detail": "password updated"})


@api_view(["POST"])
def login(request):
    email = (request.data.get("email") or "").strip()
    password = request.data.get("password") or ""
    user = User.objects.filter(email__iexact=email).first()
    if user is None or not user.check_password(password):
        return Response({"detail": "invalid credentials"}, status=status.HTTP_401_UNAUTHORIZED)
    role = "admin" if user.is_staff else "agent"
    return Response({"token": issue_token(user, role), "role": role, "email": user.email})


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def chats(request):
    user = request.user
    rows = Chat.objects.all() if user.is_staff else Chat.objects.filter(owner=user)
    data = [{"id": c.id, "agent": c.agent, "body": c.body,
             "created": c.created.isoformat()} for c in rows]
    return Response({"count": len(data), "results": data})


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def users(request):
    if not request.user.is_staff:
        return Response({"detail": "admin only"}, status=status.HTTP_403_FORBIDDEN)
    data = [{"id": u.id, "email": u.email, "username": u.username,
             "is_staff": u.is_staff} for u in User.objects.all().order_by("id")]
    return Response({"count": len(data), "results": data})
