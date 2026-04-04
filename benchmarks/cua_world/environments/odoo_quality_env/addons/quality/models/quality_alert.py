# -*- coding: utf-8 -*-
from odoo import api, fields, models


class QualityAlert(models.Model):
    _name = 'quality.alert'
    _description = 'Quality Alert'
    _inherit = ['mail.thread', 'mail.activity.mixin']
    _order = 'priority desc, id desc'

    name = fields.Char(string='Name', required=True, tracking=True)
    description = fields.Text(string='Description')
    stage_id = fields.Many2one(
        'quality.alert.stage',
        string='Stage',
        required=True,
        tracking=True,
        group_expand='_read_group_stage_ids',
        default=lambda self: self._default_stage_id(),
    )
    team_id = fields.Many2one('quality.alert.team', string='Quality Team', tracking=True)
    partner_id = fields.Many2one('res.partner', string='Vendor/Customer')
    user_id = fields.Many2one(
        'res.users', string='Responsible',
        default=lambda self: self.env.user,
        tracking=True,
    )
    priority = fields.Selection([
        ('0', 'Normal'),
        ('1', 'High'),
        ('2', 'Urgent'),
        ('3', 'Blocker'),
    ], string='Priority', default='0', tracking=True)
    product_id = fields.Many2one('product.product', string='Product')
    product_tmpl_id = fields.Many2one(
        'product.template', string='Product Template',
        related='product_id.product_tmpl_id', store=True, readonly=True,
    )
    lot_id = fields.Many2one('stock.lot', string='Lot/Serial Number')
    picking_id = fields.Many2one('stock.picking', string='Picking')
    corrective_action = fields.Html(string='Corrective Action')
    preventive_action = fields.Html(string='Preventive Action')
    date = fields.Datetime(string='Date', default=fields.Datetime.now)
    date_close = fields.Datetime(string='Date Closed')
    active = fields.Boolean(default=True)
    color = fields.Integer(string='Color Index', default=0)

    @api.model
    def _default_stage_id(self):
        stage = self.env['quality.alert.stage'].search([], order='sequence asc', limit=1)
        return stage.id if stage else False

    @api.model
    def _read_group_stage_ids(self, stages, domain, order):
        return stages.search([], order='sequence asc')
