from django.conf import settings
from django.conf.urls.static import static
from django.urls import path

from . import views

urlpatterns = [
    path("", views.portal_home),
    path("dashboard", views.dashboard),
    path("api/", views.root),
    path("api/chat-status", views.chat_status),
    path("api/auth/password_reset", views.password_reset),
    path("api/auth/password_reset/confirm", views.password_reset_confirm),
    path("api/auth/login", views.login),
    path("api/chats", views.chats),
    path("api/users/", views.users),
]

urlpatterns += static(settings.STATIC_URL, document_root=settings.STATIC_ROOT)
