// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: MIT-0

using System.Threading;
using System.Threading.Tasks;
using Amazon.DynamoDBv2.DataModel;
using Amazon.Lambda.CloudWatchEvents;
using NSubstitute;
using NSubstitute.ExceptionExtensions;
using Unicorn.Web.Common;
using Xunit;

namespace Unicorn.Web.PublicationManagerService.Tests;

public class PublicationEvaluationEventHandlerTest
{
    public PublicationEvaluationEventHandlerTest()
    {
        TestHelpers.SetEnvironmentVariables();
    }

    [Fact]
    public async Task Approved_result_updates_property_status_to_approved()
    {
        // Arrange
        var dynamoDbContext = Substitute.For<IDynamoDBContext>();
        var propertyId = "usa/anytown/main-street/111";

        var existingProperty = new PropertyRecord
        {
            Country = "usa",
            City = "anytown",
            Street = "main-street",
            PropertyNumber = "111",
            Status = PropertyStatus.Pending,
            Images = new() { "image1.jpg" },
            Description = "A nice house"
        };

        dynamoDbContext.LoadAsync<PropertyRecord>(Arg.Any<string>(), Arg.Any<string>(), Arg.Any<CancellationToken>())
            .Returns(existingProperty);

        dynamoDbContext.SaveAsync(Arg.Any<PropertyRecord>(), Arg.Any<CancellationToken>())
            .Returns(Task.CompletedTask);

        var cloudWatchEvent = new CloudWatchEvent<PublicationEvaluationCompletedEvent>
        {
            Detail = new PublicationEvaluationCompletedEvent
            {
                PropertyId = propertyId,
                EvaluationResult = "APPROVED"
            }
        };

        var context = TestHelpers.NewLambdaContext();

        // Act
        var function = new PublicationEvaluationEventHandler(dynamoDbContext);
        await function.FunctionHandler(cloudWatchEvent, context);

        // Assert
        await dynamoDbContext.Received(1)
            .SaveAsync(Arg.Is<PropertyRecord>(p => p.Status == PropertyStatus.Approved),
                Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task Declined_result_updates_property_status_to_declined()
    {
        // Arrange
        var dynamoDbContext = Substitute.For<IDynamoDBContext>();
        var propertyId = "usa/anytown/main-street/222";

        var existingProperty = new PropertyRecord
        {
            Country = "usa",
            City = "anytown",
            Street = "main-street",
            PropertyNumber = "222",
            Status = PropertyStatus.Pending,
            Images = new() { "image1.jpg" },
            Description = "Another house"
        };

        dynamoDbContext.LoadAsync<PropertyRecord>(Arg.Any<string>(), Arg.Any<string>(), Arg.Any<CancellationToken>())
            .Returns(existingProperty);

        dynamoDbContext.SaveAsync(Arg.Any<PropertyRecord>(), Arg.Any<CancellationToken>())
            .Returns(Task.CompletedTask);

        var cloudWatchEvent = new CloudWatchEvent<PublicationEvaluationCompletedEvent>
        {
            Detail = new PublicationEvaluationCompletedEvent
            {
                PropertyId = propertyId,
                EvaluationResult = "DECLINED"
            }
        };

        var context = TestHelpers.NewLambdaContext();

        // Act
        var function = new PublicationEvaluationEventHandler(dynamoDbContext);
        await function.FunctionHandler(cloudWatchEvent, context);

        // Assert
        await dynamoDbContext.Received(1)
            .SaveAsync(Arg.Is<PropertyRecord>(p => p.Status == PropertyStatus.Declined),
                Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task Unknown_evaluation_result_does_not_update_property()
    {
        // Arrange
        var dynamoDbContext = Substitute.For<IDynamoDBContext>();
        var propertyId = "usa/anytown/main-street/333";

        var existingProperty = new PropertyRecord
        {
            Country = "usa",
            City = "anytown",
            Street = "main-street",
            PropertyNumber = "333",
            Status = PropertyStatus.Pending,
            Images = new() { "image1.jpg" },
            Description = "Yet another house"
        };

        dynamoDbContext.LoadAsync<PropertyRecord>(Arg.Any<string>(), Arg.Any<string>(), Arg.Any<CancellationToken>())
            .Returns(existingProperty);

        var cloudWatchEvent = new CloudWatchEvent<PublicationEvaluationCompletedEvent>
        {
            Detail = new PublicationEvaluationCompletedEvent
            {
                PropertyId = propertyId,
                EvaluationResult = "UNKNOWN_STATUS"
            }
        };

        var context = TestHelpers.NewLambdaContext();

        // Act
        var function = new PublicationEvaluationEventHandler(dynamoDbContext);
        await function.FunctionHandler(cloudWatchEvent, context);

        // Assert - SaveAsync should not be called for unknown result
        await dynamoDbContext.Received(0)
            .SaveAsync(Arg.Any<PropertyRecord>(), Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task Invalid_property_id_throws_publication_evaluation_event_handler_exception()
    {
        // Arrange
        var dynamoDbContext = Substitute.For<IDynamoDBContext>();

        // A property_id that cannot be split into 4 parts will cause an IndexOutOfRangeException
        var cloudWatchEvent = new CloudWatchEvent<PublicationEvaluationCompletedEvent>
        {
            Detail = new PublicationEvaluationCompletedEvent
            {
                PropertyId = "invalid",
                EvaluationResult = "APPROVED"
            }
        };

        var context = TestHelpers.NewLambdaContext();

        // Act & Assert
        var function = new PublicationEvaluationEventHandler(dynamoDbContext);
        await Assert.ThrowsAsync<PublicationEvaluationEventHandlerException>(
            () => function.FunctionHandler(cloudWatchEvent, context));
    }
}
