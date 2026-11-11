from urllib.parse import urlparse

from django.conf import settings
from django.db import migrations


def set_site(apps, schema_editor):
    """Name the Site after the white-label brand.

    allauth puts ``site.name`` into email subjects and bodies, so it must not
    keep the upstream "Brightbean" set by 0004.
    """
    Site = apps.get_model("sites", "Site")
    Site.objects.update_or_create(
        id=1,
        defaults={
            "domain": urlparse(settings.APP_URL).netloc or "localhost",
            "name": settings.BRAND["name"],
        },
    )


class Migration(migrations.Migration):
    dependencies = [
        ("accounts", "0005_add_review_banner_dismissed_at"),
    ]
    operations = [migrations.RunPython(set_site, migrations.RunPython.noop)]
