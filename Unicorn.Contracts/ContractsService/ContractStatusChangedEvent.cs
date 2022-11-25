// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: MIT-0

using System;

namespace Unicorn.Contracts.ContractService;

/// <summary>
/// Class that represents an event when the status of the contract has changed.
/// </summary>
[Serializable]
public class ContractStatusChangedEvent : IEvent
{
    public ContractStatusChangedEvent(string propertyId, Guid contractId, string contractStatus,
        DateTime contractLastModifiedOn)
    {
        PropertyId = propertyId ?? throw new ArgumentNullException(nameof(propertyId));
        ContractId = contractId;
        ContractStatus = contractStatus ?? throw new ArgumentNullException(nameof(contractStatus));
        ContractLastModifiedOn = contractLastModifiedOn;
    }

    public string PropertyId { get; set; }
    public Guid ContractId { get; set; }
    public string ContractStatus { get; set; }
    public DateTime ContractLastModifiedOn { get; set; }
}

public interface IEvent
{
}