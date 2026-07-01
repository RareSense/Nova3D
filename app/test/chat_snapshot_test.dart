import 'package:flutter_test/flutter_test.dart';
import 'package:nova3d_frontend/features/chat/data/chat_snapshot_codec.dart';
import 'package:nova3d_frontend/shared/models/message_model.dart';

void main() {
  test('restores chat bubbles from the lightweight metadata snapshot', () {
    final now = DateTime.utc(2026, 6, 3, 12);
    final messages = [
      MessageModel(
        id: 'user-1',
        role: MessageRole.user,
        text: 'Make a desk lamp',
        createdAt: now,
        imageDataUrl: 'data:image/png;base64,abc',
      ),
      MessageModel(
        id: 'cad-1',
        role: MessageRole.assistant,
        text: 'Your 3D model is ready.',
        createdAt: now,
        isStreaming: false,
        modelUrl: 'https://example.test/lamp.glb',
        workflowId: 'state-123',
        messageType: 'asset_version',
        operation: 'articulate_3d_model',
        sourceModelUrl: 'https://example.test/source-lamp.glb',
        codeArtifact: {'url': 'https://example.test/lamp.py'},
        joints: [
          {'name': 'hinge', 'mesh': 'arm'},
        ],
      ),
    ];

    final restored = parseChatSnapshotMessages(
      buildChatSnapshotMetadata(messages),
    );

    expect(restored, hasLength(2));
    expect(restored.first.text, 'Make a desk lamp');
    // Reference images are intentionally excluded from the snapshot so the
    // conversation-list response stays bounded; they are recovered from the
    // per-message content when a conversation is opened.
    expect(restored.first.imageDataUrl, isNull);
    expect(restored.first.imageDataUrls, isEmpty);
    expect(restored.last.modelUrl, 'https://example.test/lamp.glb');
    expect(restored.last.workflowId, 'state-123');
    expect(restored.last.messageType, 'asset_version');
    expect(restored.last.isAssetVersionEvent, isTrue);
    expect(restored.last.operation, 'articulate_3d_model');
    expect(
      restored.last.sourceModelUrl,
      'https://example.test/source-lamp.glb',
    );
    expect(restored.last.codeArtifact?['url'], 'https://example.test/lamp.py');
    expect(restored.last.joints.single['name'], 'hinge');
  });
}
