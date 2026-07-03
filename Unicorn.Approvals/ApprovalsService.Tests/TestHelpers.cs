// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: MIT-0

using System;
using System.IO;
using System.Text;
using Amazon.Lambda.CloudWatchEvents;
using Amazon.Lambda.Core;
using Amazon.Lambda.DynamoDBEvents;
using Amazon.Lambda.Serialization.SystemTextJson;
using Amazon.Lambda.TestUtilities;

namespace Unicorn.Approvals.ApprovalsService.Tests;

public static class TestHelpers
{
    /// <summary>
    /// Builds a CloudWatchEvent wrapping a ContractStatusChangedEvent detail for ContractStatusChangedEventHandler tests
    /// </summary>
    public static CloudWatchEvent<ContractStatusChangedEvent> NewContractStatusChangedEvent(
        string propertyId, string contractStatus, Guid? contractId = null, DateTime? contractLastModifiedOn = null)
    {
        return new CloudWatchEvent<ContractStatusChangedEvent>
        {
            Detail = new ContractStatusChangedEvent
            {
                PropertyId = propertyId,
                ContractId = contractId ?? Guid.NewGuid(),
                ContractStatus = contractStatus,
                ContractLastModifiedOn = contractLastModifiedOn ?? DateTime.Today
            }
        };
    }

    /// <summary>
    /// Builds the Step Functions task-token input payload for WaitForContractApprovalFunction tests
    /// </summary>
    public static object NewWaitForContractApprovalInput(string propertyId, string taskToken)
    {
        return new
        {
            Input = new { PropertyId = propertyId },
            TaskToken = taskToken
        };
    }

    public static DynamoDBEvent LoadDynamoDbEventSource(string filename)
    {
        var serializer = Activator.CreateInstance(typeof(DefaultLambdaJsonSerializer)) as ILambdaSerializer;

        DynamoDBEvent ddbEvent = null;

        using (var fileStream = LoadJsonTestFile(filename))
        {
            if (serializer != null)
            {
                ddbEvent = serializer.Deserialize<DynamoDBEvent>(fileStream);
            }
        }

        return ddbEvent;
    }
    
    // This utility method takes care of removing the BOM that System.Text.Json doesn't like.
    public static MemoryStream LoadJsonTestFile(string filename)
    {
        var json = File.ReadAllText(filename);
        return new MemoryStream(Encoding.UTF8.GetBytes(json));
    }

    /// <summary>
    /// Creates new Lambda context
    /// </summary>
    /// <returns>TestLambdaContext</returns>
    public static TestLambdaContext NewLambdaContext()
    {
        return new TestLambdaContext
        {
            FunctionName = "uni-prop-local-properties-PropertiesApprovalSyncFu-JWaDc4Gm3SgL",
            FunctionVersion = "1",
            MemoryLimitInMB = 215,
            AwsRequestId = Guid.NewGuid().ToString("D")
        };
    }
    
}