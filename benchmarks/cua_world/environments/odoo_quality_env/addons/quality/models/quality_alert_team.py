# -*- coding: utf-8 -*-
from odoo import fields, models


class QualityAlertTeam(models.Model):
    _name = 'quality.alert.team'
    _description = 'Quality Alert Team'
    _inherit = ['mail.thread']

    name = fields.Char(string='Team Name', required=True)
    member_ids = fields.Many2many('res.users', string='Team Members')
    color = fields.Integer(string='Color Index', default=0)
    active = fields.Boolean(default=True)
