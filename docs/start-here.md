# Start Here

Welcome. NexusPlatform is a working portfolio — a miniature, honest replica of the data platforms that power real companies, built by one person on one workstation. It is made of 14 application projects and the infrastructure that holds them up: databases that survive failure, message queues that span regions, analytics warehouses that serve dashboards in milliseconds, machine-learning models that watch data in flight, and a Windows-native desktop suite that ties it all together. If you have never built one of these, the goal of this page is to let you try one in a few minutes and leave feeling like you understand a little more about how modern software is assembled.

## What you're looking at

This repository is the plan, not the code. Every piece of the platform lives in its own repository on GitHub under [github.com/grezap](https://github.com/grezap). This meta-repo is the map: it describes what each project does, which skills it demonstrates, how its pieces connect, and — most importantly for a visitor — how to watch or run a guided tour that shows the project working end-to-end. Fourteen such tours exist, one per application project, plus a grand-finale tour that traces a single customer order through every system at once.

## Pick a scenario

| ID | Title | Persona | Duration |
|---|---|---|---|
| DEMO-01 | Place an order, watch it flow everywhere | data-architect | 6 min |
| DEMO-02 | Detect a fraudulent transaction in real time | AI-forward | 5 min |
| DEMO-03 | Onboard a new SaaS tenant | CTO | 4 min |
| DEMO-04 | Ask LocalMind about your own portfolio | AI-forward | 5 min |
| DEMO-05 | Inspect a defect in a product image | AI-forward | 4 min |
| DEMO-06 | Forecast next-hour trading ticks | data-architect | 6 min |
| DEMO-07 | Personalized recommendations emerge from interactions | AI-forward | 5 min |
| DEMO-08 | Survive a Kafka region failure | CTO | 7 min |
| DEMO-09 | Catch a query regression with AI rewrite | data-architect | 6 min |
| DEMO-10 | Field-sync offline-first | CTO | 5 min |
| DEMO-11 | Native Windows DBA tour | recruiter | 4 min |
| DEMO-12 | Lakehouse Bronze to Silver to Gold | data-architect | 8 min |
| DEMO-13 | Chaos: kill a broker, survive gracefully | CTO | 6 min |
| DEMO-14 | Traverse a single order's entire journey | recruiter | 10 min |

Recruiters typically start with DEMO-11 or DEMO-14. Technical leaders usually prefer DEMO-08 or DEMO-13. Data architects gravitate to DEMO-01, DEMO-09, and DEMO-12. AI-curious viewers enjoy DEMO-02, DEMO-04, and DEMO-07.

## Two ways to experience this

**(a) Watch.** Every scenario has an auto-recorded video (MP4) and an animated GIF, produced by the same scripts that power the scenario itself. Alongside each recording sits a written step-by-step playbook with annotated screenshots so you can read at your own pace. Nothing is staged; nothing is faked. If a cluster goes down in the video, the cluster actually went down.

**(b) Run it yourself.** If you have cloned the portfolio and booted the appropriate environment (see the MASTER-PLAN's environment targets — you never need the full fleet for a single demo), a single command brings any scenario to life:

```
nexus-cli demo run DEMO-01
```

Add `--reset` to start from a clean slate. Use `nexus-cli demo trail DEMO-01` to follow the same trail in observability tools (Grafana dashboards, Jaeger traces, Seq logs) without touching the data path yourself.

## When you see something interesting

Every playbook links to the relevant section of the [`MASTER-PLAN.md`](../MASTER-PLAN.md) so you can drop from the narrative straight into the architectural reasoning. From there, follow the links into [`docs/skills-coverage.md`](./skills-coverage.md) to see which of the four portfolio dimensions — .NET engineering and architecture, advanced SQL and analytics, Python, DevOps literacy — that piece of the project exercises, and why it was built that way.

If a tool name comes up that you don't recognise — *Vault, Consul, Nomad, Iceberg, Kafka Connect, ksqlDB, Patroni, Marquez, Trivy, …* — open the [tool stack glossary](./glossary.md). It explains what each one **is** in plain English (universal definition first, NexusPlatform-specific role second), grouped by where in the stack it sits.

Enjoy the tour. If something looks wrong or unclear, the author's contact details are in the repository root.
