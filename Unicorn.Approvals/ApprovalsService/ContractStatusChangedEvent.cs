// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: MIT-0

using Amazon.DynamoDBv2.DataModel;

namespace Unicorn.Approvals.ApprovalsService;

/// <summary>
/// Represents an event when the status of the contract has changed.
/// </summary>
[Serializable]
public class ContractStatusChangedEvent : IEvent
{
    [DynamoDBHashKey]
    public string PropertyId { get; set; } = null!;
    public Guid ContractId { get; set; }
    public string ContractStatus { get; set; } = null!;
    /// <summary>
    /// Last modification time, kept as the string the Contracts service wrote (<c>yyyy-MM-ddTHH:mm:ssZ</c>).
    /// It is stored back unchanged, so it must not be parsed into a date type:
    /// the DynamoDB SDK would rewrite it as <c>yyyy-MM-ddTHH:mm:ss.fffZ</c>.
    /// </summary>
    public string ContractLastModifiedOn { get; set; } = null!;
}

public interface IEvent
{
}