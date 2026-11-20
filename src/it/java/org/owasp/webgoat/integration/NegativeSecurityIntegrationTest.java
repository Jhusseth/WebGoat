/*
 * SPDX-FileCopyrightText: Copyright © 2026 WebGoat authors
 * SPDX-License-Identifier: GPL-2.0-or-later
 */
package org.owasp.webgoat.integration;

import static io.restassured.RestAssured.given;
import static org.assertj.core.api.Assertions.assertThat;
import static org.hamcrest.Matchers.containsString;

import io.restassured.RestAssured;
import java.util.UUID;
import org.junit.jupiter.api.Test;

/**
 * Negative security tests for the controls that protect the WebGoat container itself.
 *
 * <p>Every test asserts that a request which should not be accepted is actually rejected. When the
 * matching control is removed the test is expected to fail, which is how we verify the test really
 * exercises that control:
 *
 * <ul>
 *   <li>authentication: {@code GET /service/reportcard.mvc} without a session
 *   <li>authorization: {@code GET /service/admin/users} with a regular user
 *   <li>input validation: {@code POST /register.mvc} with mismatched passwords
 *   <li>error handling: unknown user in {@code GET /service/admin/users/{username}}
 * </ul>
 */
public class NegativeSecurityIntegrationTest extends IntegrationTest {

  private static final String REPORT_CARD = "service/reportcard.mvc";
  private static final String ADMIN_USERS = "service/admin/users";
  private static final String REGISTRATION = "register.mvc";

  @Test
  void unauthenticatedRequestToReportCardIsRejected() {
    given()
        .relaxedHTTPSValidation()
        .redirects()
        .follow(false)
        .when()
        .get(webGoatUrlConfig.url(REPORT_CARD))
        .then()
        .statusCode(302)
        .header("Location", containsString("/login"));
  }

  @Test
  void regularUserCannotAccessAdminEndpoints() {
    String session = loginAs("webgoat-user", "webgoat");

    given()
        .relaxedHTTPSValidation()
        .cookie("JSESSIONID", session)
        .when()
        .get(webGoatUrlConfig.url(ADMIN_USERS))
        .then()
        .statusCode(403);
  }

  @Test
  void registrationWithMismatchedPasswordsIsRejected() {
    String username = "neg-test-" + UUID.randomUUID().toString().substring(0, 8);

    given()
        .relaxedHTTPSValidation()
        .formParam("username", username)
        .formParam("password", "secret1")
        .formParam("matchingPassword", "secret2")
        .formParam("agree", "agree")
        .post(webGoatUrlConfig.url(REGISTRATION))
        .then()
        .statusCode(200)
        .body(containsString("register.mvc"));

    given()
        .relaxedHTTPSValidation()
        .redirects()
        .follow(false)
        .formParam("username", username)
        .formParam("password", "secret1")
        .post(webGoatUrlConfig.url("login"))
        .then()
        .statusCode(302)
        .header("Location", containsString("error"));
  }

  @Test
  void unknownAdminResourceReturnsNotFoundWithoutLeakingInternals() {
    String session = loginAs("webgoat-admin", "webgoat");

    String body =
        given()
            .relaxedHTTPSValidation()
            .cookie("JSESSIONID", session)
            .when()
            .get(webGoatUrlConfig.url(ADMIN_USERS + "/usuario-que-no-existe"))
            .then()
            .statusCode(404)
            .extract()
            .asString();

    assertThat(body).doesNotContain("Exception", "org.springframework", "java.lang");
  }

  private String loginAs(String username, String password) {
    return RestAssured.given()
        .relaxedHTTPSValidation()
        .formParam("username", username)
        .formParam("password", password)
        .post(webGoatUrlConfig.url("login"))
        .then()
        .statusCode(302)
        .extract()
        .cookie("JSESSIONID");
  }
}
