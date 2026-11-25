from django.contrib.auth.models import User
from django.db import models


class Chat(models.Model):
    owner = models.ForeignKey(User, on_delete=models.CASCADE, related_name="chats")
    agent = models.CharField(max_length=64)
    body = models.TextField()
    created = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["id"]


class ResetToken(models.Model):
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name="reset_tokens")
    token = models.CharField(max_length=64, unique=True)
    used = models.BooleanField(default=False)
    created = models.DateTimeField(auto_now_add=True)
