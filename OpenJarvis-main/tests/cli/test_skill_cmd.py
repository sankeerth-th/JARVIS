"""Tests for the ``jarvis skill`` CLI commands."""

from __future__ import annotations

from click.testing import CliRunner

from openjarvis.cli import cli


class TestSkillCmd:
    def test_skill_list_help(self) -> None:
        result = CliRunner().invoke(cli, ["skill", "list", "--help"])
        assert result.exit_code == 0

    def test_skill_install_help(self) -> None:
        result = CliRunner().invoke(cli, ["skill", "install", "--help"])
        assert result.exit_code == 0

    def test_skill_search_help(self) -> None:
        result = CliRunner().invoke(cli, ["skill", "search", "--help"])
        assert result.exit_code == 0

    def test_skill_group_help(self) -> None:
        result = CliRunner().invoke(cli, ["skill", "--help"])
        assert result.exit_code == 0
        assert "list" in result.output
        assert "install" in result.output
        assert "remove" in result.output
        assert "search" in result.output
