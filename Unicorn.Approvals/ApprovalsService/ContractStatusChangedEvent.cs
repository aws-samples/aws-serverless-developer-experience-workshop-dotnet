// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: MIT-0

namespace Unicorn.Approvals.ApprovalsService;
/// <summary>
/// Represents an event when the status of the contract has changed.
/// </summary>
[Serializable]
public class ContractStatusChangedEvent : IEvent
{
    public string PropertyId { get; set; } = null!;
    public Guid ContractId { get; set; }
    public string ContractStatus { get; set; } = null!;
    public DateTime ContractLastModifiedOn { get; set; }
}

public interface IEvent
{
}