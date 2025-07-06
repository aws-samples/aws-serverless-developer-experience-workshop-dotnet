// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: MIT-0

using Amazon.DynamoDBv2.DataModel;

namespace Unicorn.Approvals.ApprovalsService;
/// <summary>
/// Represents the model for the items in the contract status DynamoDb table.
/// </summary>
public class ContractStatusItem
{
    [DynamoDBHashKey]
    public string? PropertyId { get; set; }
    
    public Guid? ContractId { get; set; }
    
    public string? ContractStatus { get; set; }
    
    public DateTime? ContractLastModifiedOn { get; set; }
    
    public string? SfnWaitApprovedTaskToken { get; set; }
}