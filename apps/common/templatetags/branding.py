"""White-label brand values for templates.

Registered as a template builtin (see ``TEMPLATES["OPTIONS"]["builtins"]``), so
``{% brand "name" %}`` works in every template without ``{% load %}``,
including emails rendered with ``render_to_string`` and no request.
"""

from django import template
from django.conf import settings

register = template.Library()


@register.simple_tag
def brand(key):
    """Return ``settings.BRAND[key]``, e.g. ``{% brand "product_name" %}``."""
    return settings.BRAND[key]
