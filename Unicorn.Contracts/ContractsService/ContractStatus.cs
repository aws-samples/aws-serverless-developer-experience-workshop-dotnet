// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: MIT-0

namespace Unicorn.Contracts.ContractService;

/// <summary>
/// Represents the status of a Contract
/// </summary>
public static class ContractStatus
{
    public const string Approved = "APPROVED";
    public const string Cancelled = "CANCELLED";
    public const string Closed = "CLOSED";
    public const string Draft = "DRAFT";
    public const string Expired = "EXPIRED";
}