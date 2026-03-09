# -*- coding: utf-8 -*-
from odoo import api, fields, models


class QualityCheck(models.Model):
    _name = 'quality.check'
    _description = 'Quality Check'
    _inherit = ['mail.thread', 'mail.activity.mixin']
    _order = 'id desc'

    name = fields.Char(string='Name', required=True)
    point_id = fields.Many2one('quality.point', string='Control Point')
    quality_state = fields.Selection([
        ('none', 'To Do'),
        ('pass', 'Passed'),
        ('fail', 'Failed'),
    ], string='Result', default='none', tracking=True)
    product_id = fields.Many2one('product.product', string='Product')
    product_tmpl_id = fields.Many2one(
        'product.template', string='Product Template',
        related='product_id.product_tmpl_id', store=True, readonly=True,
    )
    lot_id = fields.Many2one('stock.lot', string='Lot/Serial Number')
    picking_id = fields.Many2one('stock.picking', string='Picking')
    team_id = fields.Many2one('quality.alert.team', string='Quality Team')
    user_id = fields.Many2one(
        'res.users', string='Responsible',
        default=lambda self: self.env.user,
    )
    note = fields.Html(string='Notes')
    date = fields.Datetime(string='Date', default=fields.Datetime.now)
    alert_ids = fields.One2many('quality.alert', 'picking_id', string='Alerts')

    def do_pass(self):
        self.write({'quality_state': 'pass'})

    def do_fail(self):
        self.write({'quality_state': 'fail'})
