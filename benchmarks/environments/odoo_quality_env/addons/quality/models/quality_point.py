# -*- coding: utf-8 -*-
from odoo import fields, models


class QualityPoint(models.Model):
    _name = 'quality.point'
    _description = 'Quality Control Point'
    _inherit = ['mail.thread']

    name = fields.Char(string='Title', required=True)
    sequence = fields.Integer(string='Sequence', default=1)
    product_ids = fields.Many2many(
        'product.product',
        'quality_point_product_rel',
        'point_id', 'product_id',
        string='Products',
    )
    product_tmpl_ids = fields.Many2many(
        'product.template',
        'quality_point_product_tmpl_rel',
        'point_id', 'product_tmpl_id',
        string='Product Templates',
    )
    picking_type_ids = fields.Many2many(
        'stock.picking.type',
        'quality_point_picking_type_rel',
        'point_id', 'picking_type_id',
        string='Operation Types',
    )
    team_id = fields.Many2one('quality.alert.team', string='Quality Team')
    test_type = fields.Selection([
        ('instructions', 'Instructions'),
        ('passfail', 'Pass - Fail'),
        ('measure', 'Measure'),
        ('picture', 'Take a Picture'),
    ], string='Control Type', default='instructions', required=True)
    note = fields.Html(string='Instructions')
    failure_message = fields.Html(string='Message if Failure')
    message_on_failure = fields.Html(string='Warning Message')
    active = fields.Boolean(default=True)
    check_count = fields.Integer(string='Checks', compute='_compute_check_count')

    def _compute_check_count(self):
        for rec in self:
            rec.check_count = self.env['quality.check'].search_count(
                [('point_id', '=', rec.id)]
            )
