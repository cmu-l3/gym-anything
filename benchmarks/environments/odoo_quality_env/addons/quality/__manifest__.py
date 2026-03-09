# -*- coding: utf-8 -*-
{
    'name': 'Quality',
    'version': '17.0.1.0.0',
    'category': 'Manufacturing/Quality',
    'summary': 'Quality Alerts, Control Points, and Checks',
    'description': """
Quality Management System
=========================
Manage quality alerts, control points, and checks.

Features:
- Quality Alerts: Track quality issues with stages and priorities
- Quality Control Points: Define inspection checkpoints
- Quality Checks: Record inspection results (Pass/Fail)
- Quality Teams: Organize quality personnel
    """,
    'depends': ['base', 'mail', 'stock'],
    'data': [
        'security/ir.model.access.csv',
        'data/quality_stage_data.xml',
        'views/quality_alert_team_views.xml',
        'views/quality_alert_views.xml',
        'views/quality_point_views.xml',
        'views/quality_check_views.xml',
        'views/quality_menu.xml',
    ],
    'installable': True,
    'auto_install': False,
    'application': True,
    'license': 'LGPL-3',
}
