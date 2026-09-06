# platform-commerce

Commerce service (antinvestor/service-commerce `apps/default`): shops,
catalog, carts, orders, hosted checkout hand-off, fulfilment, B2B pricing,
end-of-day ledger posting. Product surface `api.stawi.org/commerce`.

Peers (via the path gateway): checkout, ledger, notification, trustage.
Trustage calls back into `api.stawi.org/commerce` for the scheduled
reconciliation and end-of-day posting using its own service identity
(`/commerce` audience + `service_commerce:ledger_post` grant, seeded in
service-authentication).

Image ships from the service repo on each `v*.*.*` tag via `cloudrun-ship`
(runtime SA must be allow-listed with `scripts/bootstrap-cloudrun-ship.sh`).
