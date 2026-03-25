// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: MIT-0

using System.Text.Json;
using Amazon.DynamoDBv2.DataModel;
using Amazon.EventBridge;
using Amazon.EventBridge.Model;
using Amazon.Lambda.SQSEvents;
using FizzWare.NBuilder;
using NSubstitute;
using Unicorn.Web.Common;
using Xunit;

namespace Unicorn.Web.PublicationManagerService.Tests;

public class RequestApprovalFunctionTest
{
    public RequestApprovalFunctionTest()
    {
        TestHelpers.SetEnvironmentVariables();
        // Set env variable for Powertools Metrics 
        Environment.SetEnvironmentVariable("POWERTOOLS_METRICS_NAMESPACE", "ContractService");
    }

    [Fact]
    public async Task Publish_event_when_property_status_is_pending_or_declined()
    {
        // Arrange
        var eventPayload = Builder<ApiGwSqsPayload>.CreateNew()
            .With(x => x.PropertyId = "usa/anytown/main-street/777")
            .Build();
        
        var context = TestHelpers.NewLambdaContext();
        var dynamoDbContext = Substitute.For<IDynamoDBContext>();
        var eventBindingClient = Substitute.For<IAmazonEventBridge>();

        var sqsEvent = new SQSEvent()
        {
            Records = new List<SQSEvent.SQSMessage>
            {
                new()
                {
                    Body = JsonSerializer.Serialize(eventPayload)
                }
            }
        };
        
        var searchResult = new List<PropertyRecord>
        {
            new()
            {
                Country = "USA",
                City = "Anytown",
                Street = "Main Street",
                PropertyNumber = "123",
                ListPrice = 2000000.00M,
                Images = new() { "image1.jpg", "image2.jpg", "image3.jpg" },
                Status = PropertyStatus.Pending
            },
            new()
            {
                Country = "USA",
                City = "Anytown",
                Street = "Main Street",
                PropertyNumber = "123",
                ListPrice = 2000000.00M,
                Images = new() { "image1.jpg", "image2.jpg", "image3.jpg" },
                Status = PropertyStatus.Declined
            }
        };

        dynamoDbContext
            .FromQueryAsync<PropertyRecord>(Arg.Any<Amazon.DynamoDBv2.DocumentModel.QueryOperationConfig>())
            .Returns(TestHelpers.NewDynamoDBSearchResult(searchResult));

        eventBindingClient.PutEventsAsync(Arg.Any<PutEventsRequest>(), Arg.Any<CancellationToken>())
            .Returns(new PutEventsResponse { FailedEntryCount = 0 });

        // Act
        var function = new RequestApprovalFunction(dynamoDbContext, eventBindingClient);
        await function.FunctionHandler(sqsEvent, context);

        // Assert
        dynamoDbContext.Received(1)
            .FromQueryAsync<PropertyRecord>(Arg.Any<Amazon.DynamoDBv2.DocumentModel.QueryOperationConfig>());

        await eventBindingClient.Received(1)
            .PutEventsAsync(
                Arg.Is<PutEventsRequest>(r => r.Entries.First().DetailType == "PublicationApprovalRequested"),
                Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task Do_not_publish_event_when_property_status_is_approved()
    {
        // Arrange
        var eventPayload = Builder<ApiGwSqsPayload>.CreateNew()
            .With(x => x.PropertyId = "usa/anytown/main-street/777")
            .Build();
        var context = TestHelpers.NewLambdaContext();

        var dynamoDbContext = Substitute.For<IDynamoDBContext>();
        var eventBindingClient = Substitute.For<IAmazonEventBridge>();

        var sqsEvent = new SQSEvent()
        {
            Records = new List<SQSEvent.SQSMessage>
            {
                new()
                {
                    Body = JsonSerializer.Serialize(eventPayload)
                }
            }
        };
        
        var searchResult = new List<PropertyRecord>
        {
            new()
            {
                Country = "USA",
                City = "Anytown",
                Street = "Main Street",
                PropertyNumber = "123",
                ListPrice = 2000000.00M,
                Images = new() { "image1.jpg", "image2.jpg", "image3.jpg" },
                Status = PropertyStatus.Approved
            }
        };

        // Act
        var function = new RequestApprovalFunction(dynamoDbContext, eventBindingClient);
        await function.FunctionHandler(sqsEvent, context);

        // Assert
        
        dynamoDbContext
            .FromQueryAsync<PropertyRecord>(Arg.Any<Amazon.DynamoDBv2.DocumentModel.QueryOperationConfig>())
            .Returns(TestHelpers.NewDynamoDBSearchResult(searchResult));
        
        dynamoDbContext.Received(1)
            .FromQueryAsync<PropertyRecord>(Arg.Any<Amazon.DynamoDBv2.DocumentModel.QueryOperationConfig>());
        
        eventBindingClient.PutEventsAsync(Arg.Any<PutEventsRequest>(), Arg.Any<CancellationToken>())
            .Returns(new PutEventsResponse { FailedEntryCount = 0 });
            
        await eventBindingClient.Received(0)
            .PutEventsAsync(
                Arg.Is<PutEventsRequest>(r => r.Entries.First().DetailType == "PublicationApprovalRequested"),
                Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task Invalid_property_id_does_not_publish_event()
    {
        // Arrange
        var eventPayload = Builder<ApiGwSqsPayload>.CreateNew()
            .With(x => x.PropertyId = "INVALID!!!")
            .Build();

        var context = TestHelpers.NewLambdaContext();
        var dynamoDbContext = Substitute.For<IDynamoDBContext>();
        var eventBindingClient = Substitute.For<IAmazonEventBridge>();

        var sqsEvent = new SQSEvent()
        {
            Records = new List<SQSEvent.SQSMessage>
            {
                new()
                {
                    Body = JsonSerializer.Serialize(eventPayload)
                }
            }
        };

        // Act
        var function = new RequestApprovalFunction(dynamoDbContext, eventBindingClient);
        await function.FunctionHandler(sqsEvent, context);

        // Assert - invalid property_id should cause early return, no EventBridge call
        await eventBindingClient.Received(0)
            .PutEventsAsync(Arg.Any<PutEventsRequest>(), Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task Property_not_found_does_not_publish_event()
    {
        // Arrange
        var eventPayload = Builder<ApiGwSqsPayload>.CreateNew()
            .With(x => x.PropertyId = "usa/anytown/main-street/000")
            .Build();

        var context = TestHelpers.NewLambdaContext();
        var dynamoDbContext = Substitute.For<IDynamoDBContext>();
        var eventBindingClient = Substitute.For<IAmazonEventBridge>();

        var sqsEvent = new SQSEvent()
        {
            Records = new List<SQSEvent.SQSMessage>
            {
                new()
                {
                    Body = JsonSerializer.Serialize(eventPayload)
                }
            }
        };

        // Return empty list - no property found
        var emptyResult = new List<PropertyRecord>();
        dynamoDbContext
            .FromQueryAsync<PropertyRecord>(Arg.Any<Amazon.DynamoDBv2.DocumentModel.QueryOperationConfig>())
            .Returns(TestHelpers.NewDynamoDBSearchResult(emptyResult));

        // Act
        var function = new RequestApprovalFunction(dynamoDbContext, eventBindingClient);
        await function.FunctionHandler(sqsEvent, context);

        // Assert - no property means no EventBridge event
        await eventBindingClient.Received(0)
            .PutEventsAsync(Arg.Any<PutEventsRequest>(), Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task EventBridge_failure_is_caught_and_does_not_throw()
    {
        // Arrange
        var eventPayload = Builder<ApiGwSqsPayload>.CreateNew()
            .With(x => x.PropertyId = "usa/anytown/main-street/777")
            .Build();

        var context = TestHelpers.NewLambdaContext();
        var dynamoDbContext = Substitute.For<IDynamoDBContext>();
        var eventBindingClient = Substitute.For<IAmazonEventBridge>();

        var sqsEvent = new SQSEvent()
        {
            Records = new List<SQSEvent.SQSMessage>
            {
                new()
                {
                    Body = JsonSerializer.Serialize(eventPayload)
                }
            }
        };

        var searchResult = new List<PropertyRecord>
        {
            new()
            {
                Country = "USA",
                City = "Anytown",
                Street = "Main Street",
                PropertyNumber = "777",
                ListPrice = 2000000.00M,
                Images = new() { "image1.jpg" },
                Status = PropertyStatus.Pending
            }
        };

        dynamoDbContext
            .FromQueryAsync<PropertyRecord>(Arg.Any<Amazon.DynamoDBv2.DocumentModel.QueryOperationConfig>())
            .Returns(TestHelpers.NewDynamoDBSearchResult(searchResult));

        // Simulate EventBridge returning failed entries
        eventBindingClient.PutEventsAsync(Arg.Any<PutEventsRequest>(), Arg.Any<CancellationToken>())
            .Returns(new PutEventsResponse { FailedEntryCount = 1 });

        // Act - the exception from failed entries is caught by the outer try/catch
        var function = new RequestApprovalFunction(dynamoDbContext, eventBindingClient);
        await function.FunctionHandler(sqsEvent, context);

        // Assert - PutEventsAsync was called but the failure was caught
        await eventBindingClient.Received(1)
            .PutEventsAsync(Arg.Any<PutEventsRequest>(), Arg.Any<CancellationToken>());
    }
}

public class ApiGwSqsPayload
{
    [System.Text.Json.Serialization.JsonPropertyName("property_id")]
    public required string PropertyId { get; set; }
}