// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: MIT-0

using System;
using System.Threading;
using System.Threading.Tasks;
using Amazon.DynamoDBv2.DataModel;
using Amazon.Lambda.CloudWatchEvents;
using NSubstitute;
using NSubstitute.ExceptionExtensions;
using Xunit;
using Xunit.Abstractions;

namespace Unicorn.Approvals.ApprovalsService.Tests;

[Collection("Sequential")]
public class ContractStatusChangedEventHandlerTest
{
    private readonly ITestOutputHelper _testOutputHelper;

    public ContractStatusChangedEventHandlerTest(ITestOutputHelper testOutputHelper)
    {
        _testOutputHelper = testOutputHelper;
        // Set env variable for Powertools Metrics
        Environment.SetEnvironmentVariable("POWERTOOLS_METRICS_NAMESPACE", "ContractService");
        Environment.SetEnvironmentVariable("CONTRACT_STATUS_TABLE", "test-contract-status-table");
    }

    [Fact]
    public async Task Valid_event_saves_contract_status_to_dynamodb()
    {
        // Arrange
        var mockDynamoDbContext = Substitute.For<IDynamoDBContext>();
        mockDynamoDbContext.SaveAsync(Arg.Any<ContractStatusChangedEvent>(), Arg.Any<CancellationToken>())
            .Returns(Task.CompletedTask);

        var cloudWatchEvent = new CloudWatchEvent<ContractStatusChangedEvent>
        {
            Detail = new ContractStatusChangedEvent
            {
                PropertyId = "usa/anytown/main-street/111",
                ContractId = Guid.NewGuid(),
                ContractStatus = "DRAFT",
                ContractLastModifiedOn = DateTime.Today
            }
        };

        var context = TestHelpers.NewLambdaContext();

        // Act
        var function = new ContractStatusChangedEventHandler(mockDynamoDbContext);
        await function.FunctionHandler(cloudWatchEvent, context);

        // Assert
        await mockDynamoDbContext.Received(1)
            .SaveAsync(Arg.Is<ContractStatusChangedEvent>(e =>
                e.PropertyId == "usa/anytown/main-street/111" &&
                e.ContractStatus == "DRAFT"), Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task Malformed_event_throws_contract_status_changed_event_handler_exception()
    {
        // Arrange
        var mockDynamoDbContext = Substitute.For<IDynamoDBContext>();
        mockDynamoDbContext.SaveAsync(Arg.Any<ContractStatusChangedEvent>(), Arg.Any<CancellationToken>())
            .ThrowsAsync(new ArgumentException("Invalid event data"));

        var cloudWatchEvent = new CloudWatchEvent<ContractStatusChangedEvent>
        {
            Detail = new ContractStatusChangedEvent
            {
                PropertyId = "",
                ContractId = Guid.Empty,
                ContractStatus = "",
                ContractLastModifiedOn = DateTime.MinValue
            }
        };

        var context = TestHelpers.NewLambdaContext();

        // Act & Assert
        var function = new ContractStatusChangedEventHandler(mockDynamoDbContext);
        await Assert.ThrowsAsync<ContractStatusChangedEventHandlerException>(
            () => function.FunctionHandler(cloudWatchEvent, context));
    }

    [Fact]
    public async Task DynamoDB_failure_throws_contract_status_changed_event_handler_exception()
    {
        // Arrange
        var mockDynamoDbContext = Substitute.For<IDynamoDBContext>();
        mockDynamoDbContext.SaveAsync(Arg.Any<ContractStatusChangedEvent>(), Arg.Any<CancellationToken>())
            .ThrowsAsync(new Exception("DynamoDB service unavailable"));

        var cloudWatchEvent = new CloudWatchEvent<ContractStatusChangedEvent>
        {
            Detail = new ContractStatusChangedEvent
            {
                PropertyId = "usa/anytown/main-street/222",
                ContractId = Guid.NewGuid(),
                ContractStatus = "APPROVED",
                ContractLastModifiedOn = DateTime.Today
            }
        };

        var context = TestHelpers.NewLambdaContext();

        // Act & Assert
        var function = new ContractStatusChangedEventHandler(mockDynamoDbContext);
        var exception = await Assert.ThrowsAsync<ContractStatusChangedEventHandlerException>(
            () => function.FunctionHandler(cloudWatchEvent, context));

        Assert.Contains("DynamoDB service unavailable", exception.Message);
    }
}
