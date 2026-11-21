// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: MIT-0

using System;
using Xunit;

namespace Unicorn.Contracts.ContractService.Tests;

public class ContractTimestampTest
{
    [Fact]
    public void From_truncates_the_fraction_instead_of_rounding()
    {
        var instant = new DateTime(2026, 11, 21, 2, 42, 30, 987, DateTimeKind.Utc);

        Assert.Equal("2026-11-21T02:42:30Z", ContractTimestamp.From(instant));
    }

    [Fact]
    public void From_keeps_the_same_width_when_the_fraction_is_zero()
    {
        var instant = new DateTime(2026, 11, 21, 2, 42, 30, DateTimeKind.Utc);

        Assert.Equal("2026-11-21T02:42:30Z", ContractTimestamp.From(instant));
    }

    [Fact]
    public void From_converts_a_local_instant_to_utc()
    {
        var instant = new DateTimeOffset(2026, 11, 21, 13, 42, 30, TimeSpan.FromHours(11)).LocalDateTime;

        Assert.Equal("2026-11-21T02:42:30Z", ContractTimestamp.From(instant));
    }

    [Fact]
    public void Now_matches_the_contract_timestamp_pattern()
    {
        Assert.Matches(@"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$", ContractTimestamp.Now());
    }
}
