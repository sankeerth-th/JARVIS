"""``jarvis skill`` — skill management commands."""

from __future__ import annotations

import click
from rich.console import Console
from rich.table import Table


@click.group()
def skill() -> None:
    """Manage skills — list, install, remove."""


@skill.command("list")
def list_skills() -> None:
    """List installed skills."""
    console = Console(stderr=True)
    try:
        from openjarvis.core.registry import SkillRegistry

        keys = sorted(SkillRegistry.keys())
        if not keys:
            console.print("[dim]No skills installed.[/dim]")
            return
        table = Table(title="Installed Skills")
        table.add_column("Name", style="cyan")
        table.add_column("Description", style="green")
        for key in keys:
            skill_cls = SkillRegistry.get(key)
            desc = ""
            if hasattr(skill_cls, "manifest"):
                m = skill_cls.manifest if not callable(skill_cls.manifest) else None
                if m and hasattr(m, "description"):
                    desc = m.description[:60]
            table.add_row(key, desc)
        console.print(table)
    except Exception as exc:
        console.print(f"[red]Error: {exc}[/red]")


@skill.command()
@click.argument("skill_name")
def install(skill_name: str) -> None:
    """Install a skill from the bundled library."""
    console = Console(stderr=True)
    console.print(f"[yellow]Installing skill: {skill_name}[/yellow]")
    # Skills are discovered from TOML files — point user to the right place
    console.print(
        f"[dim]Place skill TOML file in ~/.openjarvis/skills/{skill_name}.toml[/dim]"
    )


@skill.command()
@click.argument("skill_name")
def remove(skill_name: str) -> None:
    """Remove an installed skill."""
    console = Console(stderr=True)
    console.print(f"[yellow]Removing skill: {skill_name}[/yellow]")
    console.print("[dim]Skill removal not yet implemented.[/dim]")


@skill.command()
@click.argument("query", default="")
def search(query: str) -> None:
    """Search for available skills."""
    console = Console(stderr=True)
    if not query:
        console.print("[dim]Provide a search query.[/dim]")
        return
    console.print(f"[dim]Searching for skills matching '{query}'...[/dim]")
    console.print("[dim]Skill search not yet implemented.[/dim]")


__all__ = ["skill"]
