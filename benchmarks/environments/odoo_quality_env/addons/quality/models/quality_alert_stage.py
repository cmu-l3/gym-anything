# -*- coding: utf-8 -*-
from odoo import fields, models


class QualityAlertStage(models.Model):
    _name = 'quality.alert.stage'
    _description = 'Quality Alert Stage'
    _order = 'sequence, id'

    name = fields.Char(string='Stage Name', required=True, translate=True)
    sequence = fields.Integer(string='Sequence', default=1)
    done = fields.Boolean(string='Done Stage', default=False,
                          help='When checked, alerts in this stage are considered closed/done.')
    folded = fields.Boolean(string='Folded in Kanban', default=False)
