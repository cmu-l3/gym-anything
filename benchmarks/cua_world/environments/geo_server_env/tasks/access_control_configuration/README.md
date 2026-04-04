# Task: Access Control Configuration

## Domain Context

GIS Security Administrators at municipal IT departments and government agencies are responsible for implementing role-based access control (RBAC) on GeoServer instances that serve data to both internal staff and the public. A standard security hardening workflow involves creating named user accounts, defining roles for different access tiers, assigning users to roles, and then applying data-layer access rules so that sensitive layers are restricted while public layers remain open.

GeoServer's security model uses Users → Roles → Access Rules (both data-level and service-level). Configuring this correctly requires navigating three distinct sections of the admin UI: Users/Groups/Roles, Data Security, and Service Security.

## Occupation

**Geographic Information Systems Technologists and Technicians** — administering GeoServer security, managing user accounts, and controlling layer-level data access for a multi-tenant geospatial platform.

---

## Goal

Configure role-based access control on GeoServer:

1. **Create user** `gis_reader` with password `GisR3ader2024!`
2. **Create role** `ROLE_GIS_READER`
3. **Assign** user `gis_reader` to role `ROLE_GIS_READER`
4. **Create a data access security rule** for the `ne` workspace:
   - Resource: `ne.*.r` (all layers in the `ne` workspace, read access)
   - Granted roles: `ROLE_GIS_READER,ROLE_AUTHENTICATED`
5. **Create a service security rule** for WMS:
   - Service: `wms`
   - Method: `GetMap`
   - Allowed: `ROLE_GIS_READER,ROLE_ANONYMOUS`

GeoServer admin: `http://localhost:8080/geoserver/web/` (admin / Admin123!)

---

## Success Criteria

| Criterion | Points |
|-----------|--------|
| User `gis_reader` exists | 20 |
| Role `ROLE_GIS_READER` exists | 20 |
| User `gis_reader` assigned to `ROLE_GIS_READER` | 20 |
| Data access rule exists for `ne.*` with `ROLE_GIS_READER` | 25 |
| Service security rule for WMS exists | 15 |
| **Total** | **100** |

**Pass threshold**: ≥60 points
**Mandatory**: User AND role must both exist to pass

---

## Verification Strategy

- User check: `GET /rest/security/usergroup/users.json` → find `gis_reader`
- Role check: `GET /rest/security/roles.json` → find `ROLE_GIS_READER`
- Role assignment: `GET /rest/security/usergroup/user/gis_reader/roles.json` → check for `ROLE_GIS_READER`
- Data rules: `GET /rest/security/acl/layers.json` → find a rule with `ne.*` pattern and role containing `GIS_READER`
- Service rules: `GET /rest/security/acl/services.json` → find a WMS rule

---

## Notes

- GeoServer security admin is under Security menu in the left panel
- Users and Roles are in separate pages: Security > Users/Groups, Security > Roles
- Data access rules: Security > Data
- Service security: Security > Services
- User password strength: GeoServer 2.25 requires ≥8 chars with mixed case and digits
- Role names conventionally use ROLE_ prefix (uppercase)
