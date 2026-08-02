# Customer data deletion (right to erasure)

Objective: delete all data tied to a customer ID across all stores within 30 days.

## Stores to purge
- [ ] Cosmos DB: `chat-history` (partition = userId), `reviews` (query by userId)
- [ ] Azure SQL: `User`, `Order`, `AuditLog`
- [ ] Blob Storage: `reviews-images/*` uploaded by the user
- [ ] Analytics: bronze/silver/gold Parquet — mark tombstone, next compaction removes
- [ ] Purview: mark customer entity purged

## Steps
1. ...
