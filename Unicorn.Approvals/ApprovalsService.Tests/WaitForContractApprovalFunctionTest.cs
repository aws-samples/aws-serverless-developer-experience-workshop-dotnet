// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: MIT-0

using System;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using Amazon.DynamoDBv2.DataModel;
using NSubstitute;
using NSubstitute.ExceptionExtensions;
using Xunit;
using Xunit.Abstractions;

namespace Unicorn.Approvals.ApprovalsService.Tests;

[Collection("Sequential")]
public class WaitForContractApprovalFunctionTest
{
    private readonly ITestOutputHelper _testOutputHelper;

    public WaitForContractApprovalFunctionTest(ITestOutputHelper testOutputHelper)
    {
        _testOutputHelper = testOutputHelper;
        // Set env variable for Powertools Metrics
        Environment.SetEnvironmentVariable("POWERTOOLS_METRICS_NAMESPACE", "ContractService");
        Environment.SetEnvironmentVariable("CONTRACT_STATUS_TABLE", "test-contract-status-table");
    }

    [Fact]
    public async Task Contract_exists_stores_token_and_returns()
    {
        // Arrange
        var mockDynamoDbContext = Substitute.For<IDynamoDBContext>();
        var propertyId = "usa/anytown/main-street/111";
        var taskToken = "test-task-token-abc123";

        var existingItem = new ContractStatusItem
        {
            PropertyId = propertyId,
            ContractId = Guid.NewGuid(),
            ContractStatus = "DRAFT",
            ContractLastModifiedOn = DateTime.Today,
            SfnWaitApprovedTaskToken = null
        };

        mockDynamoDbContext.LoadAsync<ContractStatusItem>(Arg.Is(propertyId), Arg.Any<CancellationToken>())
            .Returns(existingItem);

        mockDynamoDbContext.SaveAsync(Arg.Any<ContractStatusItem>(), Arg.Any<CancellationToken>())
            .Returns(Task.CompletedTask);

        var input = new
        {
            Input = new { PropertyId = propertyId },
            TaskToken = taskToken
        };

        var context = TestHelpers.NewLambdaContext();

        // Act
        var function = new WaitForContractApprovalFunction(mockDynamoDbContext);
        await function.FunctionHandler(input, context);

        // Assert - token should have been stored and SaveAsync called
        await mockDynamoDbContext.Received(1)
            .SaveAsync(Arg.Is<ContractStatusItem>(item =>
                item.PropertyId == propertyId &&
                item.SfnWaitApprovedTaskToken == taskToken), Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task Contract_not_found_throws_contract_status_not_found_exception()
    {
        // Arrange
        var mockDynamoDbContext = Substitute.For<IDynamoDBContext>();
        var propertyId = "usa/anytown/main-street/999";
        var taskToken = "test-task-token-abc123";

        mockDynamoDbContext.LoadAsync<ContractStatusItem>(Arg.Is(propertyId), Arg.Any<CancellationToken>())
            .Returns((ContractStatusItem?)null);

        var input = new
        {
            Input = new { PropertyId = propertyId },
            TaskToken = taskToken
        };

        var context = TestHelpers.NewLambdaContext();

        // Act & Assert
        var function = new WaitForContractApprovalFunction(mockDynamoDbContext);
        await Assert.ThrowsAsync<ContractStatusNotFoundException>(
            () => function.FunctionHandler(input, context));
    }

    [Fact]
    public async Task DynamoDB_save_failure_throws_exception()
    {
        // Arrange
        var mockDynamoDbContext = Substitute.For<IDynamoDBContext>();
        var propertyId = "usa/anytown/main-street/333";
        var taskToken = "test-task-token-xyz789";

        var existingItem = new ContractStatusItem
        {
            PropertyId = propertyId,
            ContractId = Guid.NewGuid(),
            ContractStatus = "DRAFT",
            ContractLastModifiedOn = DateTime.Today,
            SfnWaitApprovedTaskToken = null
        };

        mockDynamoDbContext.LoadAsync<ContractStatusItem>(Arg.Is(propertyId), Arg.Any<CancellationToken>())
            .Returns(existingItem);

        mockDynamoDbContext.SaveAsync(Arg.Any<ContractStatusItem>(), Arg.Any<CancellationToken>())
            .ThrowsAsync(new Exception("DynamoDB save failed"));

        var input = new
        {
            Input = new { PropertyId = propertyId },
            TaskToken = taskToken
        };

        var context = TestHelpers.NewLambdaContext();

        // Act & Assert
        var function = new WaitForContractApprovalFunction(mockDynamoDbContext);
        await Assert.ThrowsAsync<Exception>(
            () => function.FunctionHandler(input, context));
    }
}
