"""Supervisor name variants (FR-64). Run from the repository root: python3 -I tests/test_people.py"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "harvester"))
from netd import people  # noqa: E402


def check():
    m = people.canonical([
        (["Jackson Phiri"], ["Computer Studies"], []), (["J. Phiri"], ["Computer Studies"], []),
        (["John Phiri"], ["Physics"], []), (["J Phiri"], ["Physics"], []),
        (["Dr Phiri J"], [], []),                       # two J. Phiris and no department: left alone
        (["Phiri"], ["Computer Studies"], []),          # bare surname: never joined
        (["ROBert TEMBO"], [], []), (["R. Tembo"], [], []),
        (["Austin Cheyeka"], [], []), (["A. M. Cheyeka"], [], []), (["Austin Mumba Cheyeka"], [], []),
        (["Elijah Mwewa Mutambanshiku Bwalya"], [], []), (["Elijah Mutambanshiku Mwewa Bwalya"], [], []),
        (["M. Banda"], [], []), (["K. Banda"], [], []),  # initials conflict
    ])
    assert m["J. Phiri"] == "Jackson Phiri" and m["J Phiri"] == "John Phiri", m
    assert "Dr Phiri J" not in m and "Phiri" not in m, m
    assert m["ROBert TEMBO"] == "R. Tembo", m
    assert m["Austin Cheyeka"] == m["A. M. Cheyeka"] == "Austin Mumba Cheyeka", m
    assert len([v for v in m if "Bwalya" in v]) == 1, m
    assert "M. Banda" not in m and "K. Banda" not in m, m
    assert people.apply({"supervisor": ["J. Phiri", "Jackson Phiri"]}, m) == ["Jackson Phiri"]
    print("people: ok")


if __name__ == "__main__":
    check()
