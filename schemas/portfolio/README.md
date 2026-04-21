# portfolio — Schemas

## Ownership

| Store | Database / schema | Role |
|---|---|---|
| SQL Server AG | `PortfolioDb` | Site content, contact submissions, audit |
| Redis Cluster | — | Session cache, SignalR backplane, page-render cache |

**Migration tool:** FluentMigrator.
**Status:** DDL planned, authoring begins in Phase 0.K.

## SQL Server — `PortfolioDb`

Minimum 10 tables. Standard audit columns on every business table.

| Schema.Table | Description |
|---|---|
| `content.Pages` | Top-level site pages (home, about, projects, contact). Slug, title, SEO meta. |
| `content.PageSections` | Ordered sections within a page (hero, feature grid, CTA). Supports live reorder. |
| `content.Projects` | Row per portfolio project — pulls from `portfolio-index` grid. Status, links, tags. |
| `content.TechStack` | Normalized tech tags with categories (language, framework, store, infra). |
| `content.ProjectTechStack` | M:N bridge with proficiency level (primary/substantial/mentioned). |
| `content.CaseStudies` | Long-form project write-ups; problem/approach/outcome/try-it rendering. |
| `content.Demos` | Registry of the 14 DEMO playbooks; links to recordings and playbook paths. |
| `leads.ContactSubmissions` | Contact form inbox; Outbox pattern ships to Kafka + SendGrid. |
| `leads.NewsletterSubscribers` | Double-opt-in flow; unsubscribe tokens. |
| `audit.ChangeLog` | Per-table change capture via triggers. |
| `outbox.OutboxMessages` | MassTransit Outbox table — atomic DB write + Kafka publish. |
| `ops.HealthSnapshots` | Periodic home-page "is everything healthy" grid; populated from Grafana API. |

## Advanced SQL artifacts required (E28)

- Recursive CTE on `content.PageSections` to render nested sections.
- Window function ranking recent case studies by view count trend.
- FOR JSON PATH materialization of project cards for Blazor SSR.

## Redis key conventions

- `portfolio:session:{id}` — ASP.NET Core session, TTL 30m
- `portfolio:render:{pageSlug}:{version}` — rendered HTML fragment cache, TTL 5m
- `portfolio:signalr:{hub}` — SignalR backplane (Redis Cluster backplane provider)
