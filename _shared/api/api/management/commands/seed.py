import os

from django.conf import settings
from django.contrib.auth.models import User
from django.core.management.base import BaseCommand

from api.models import Chat


class Command(BaseCommand):
    help = "Seed the lab: admin, agents, chats, flag. Idempotent."

    def handle(self, *args, **options):
        admin_email = os.environ.get("ADMIN_EMAIL", "admin@corp.lab")
        admin_password = os.environ.get("ADMIN_PASSWORD", "Sup3rS3cret!2026")

        admin, created = User.objects.get_or_create(
            username="admin", defaults={"email": admin_email, "first_name": "Dana",
                                        "is_staff": True, "is_superuser": True}
        )
        admin.email = admin_email
        admin.is_staff = True
        admin.is_superuser = True
        # only seed the password on first creation so a solved reset survives a restart
        if created or not admin.has_usable_password():
            admin.set_password(admin_password)
        admin.save()

        agents = [("alex", "alex@corp.lab"), ("jordan", "jordan@corp.lab"),
                  ("sam", "sam@corp.lab")]
        for name, email in agents:
            u, _ = User.objects.get_or_create(username=name, defaults={"email": email})
            u.email = email
            u.set_password(os.environ.get("AGENT_PASSWORD", "agent-pass-2026"))
            u.save()

        if Chat.objects.count() == 0:
            for i in range(1, 7):
                Chat.objects.create(owner=admin, agent=f"agent-{i}",
                                    body=f"Live chat transcript #{i}: customer asked about billing.")
            for name, _ in agents:
                u = User.objects.get(username=name)
                for i in range(1, 4):
                    Chat.objects.create(owner=u, agent=name,
                                        body=f"{name}'s transcript #{i}: routine enquiry.")
            Chat.objects.create(owner=admin, agent="system",
                                body=f"Admin console verification token: {settings.FLAG}")

        self.stdout.write(f"seeded: users={User.objects.count()} chats={Chat.objects.count()}")
